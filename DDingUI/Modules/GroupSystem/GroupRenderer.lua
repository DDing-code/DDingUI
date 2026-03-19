-- [GROUP SYSTEM] GroupRenderer: CDM 프레임 SetParent 방식 렌더링
-- [REPARENT] ViewerLayout 동일 레이아웃 엔진 — 뷰어 설정값 100% 반영
-- FrameController.SetupFrameInContainer 통합, Blizzard CDM 프레임 직접 관리
local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
if not DDingUI then return end

local GroupRenderer = {}
DDingUI.GroupRenderer = GroupRenderer

-- Locals
local CreateFrame = CreateFrame
local math_max = math.max
local math_min = math.min
local math_ceil = math.ceil
local math_floor = math.floor
local math_abs = math.abs
local pairs = pairs
local ipairs = ipairs
local wipe = wipe
local IsInRaid = IsInRaid
local IsInGroup = IsInGroup
local C_Timer = C_Timer

-- FrameController 참조 (런타임에 resolve)
local FC -- FrameController lazy reference

local function GetFC()
    if not FC then
        FC = DDingUI.FrameController or DDingUI.CDMHookEngine
    end
    return FC
end

-- 그룹 프레임 저장소
GroupRenderer.groupFrames = {} -- [groupName] = containerFrame
GroupRenderer._forceFullSetup = false -- [FIX] Refresh 시 강제 재설정 플래그

-- ============================================================
-- [DYNAMIC] CustomIcons 내재화 헬퍼
-- ============================================================
local function GetDynamicDB()
    local profile = DDingUI.db and DDingUI.db.profile
    if not profile then return nil end
    profile.dynamicIcons = profile.dynamicIcons or {}
    local db = profile.dynamicIcons
    db.iconData = db.iconData or {}
    db.groups = db.groups or {}
    return db
end

local function IsIconActive(iconData, iconFrame)
    if not iconData then return false end

    -- spellbook 체크
    if iconData.type == "spell" and iconData.id then
        local spellInfo = C_Spell and C_Spell.GetSpellInfo(iconData.id)
        if not spellInfo then return false end
    end

    -- aura 타입: buff 활성 상태 (spellID 및 spellName 기반 폴백)
    if iconData.type == "aura" and iconData.id then
        local auraData = nil
        pcall(function() auraData = C_UnitAuras.GetPlayerAuraBySpellID(iconData.id) end)

        if not auraData and iconFrame and not iconFrame._cachedAuraSpellID then
            -- 아직 실제 buff spellID를 찾지 못한 경우 (최초 시점)
            pcall(function()
                local spellInfo = C_Spell.GetSpellInfo(iconData.id)
                if spellInfo and spellInfo.name then
                    AuraUtil.ForEachAura("player", "HELPFUL", nil, function(a)
                        if a and a.name == spellInfo.name then
                            auraData = a
                            if a.spellId and a.spellId ~= iconData.id then
                                iconFrame._cachedAuraSpellID = a.spellId
                            end
                            return true
                        end
                    end)
                end
            end)
        end

        if not auraData and iconFrame and iconFrame._cachedAuraSpellID then
            pcall(function() auraData = C_UnitAuras.GetPlayerAuraBySpellID(iconFrame._cachedAuraSpellID) end)
            -- 캐시된 ID로도 없으면 지우지 않고 유지 (같은 스펠이면 캐시는 계속 유효하므로)
        end

        if not auraData then return false end
    end

    -- loadConditions 체크
    local settings = iconData.settings
    if settings and settings.loadConditions and settings.loadConditions.enabled then
        local lc = settings.loadConditions
        if lc.specs then
            local anySpecSet = false
            for _, v in pairs(lc.specs) do
                if v then anySpecSet = true; break end
            end
            if anySpecSet then
                local currentSpec = GetSpecialization and GetSpecialization() or 0
                local specID = currentSpec and GetSpecializationInfo and GetSpecializationInfo(currentSpec) or 0
                if not lc.specs[specID] then return false end
            end
        end
        if lc.inCombat and not InCombatLockdown() then return false end
        if lc.outOfCombat and InCombatLockdown() then return false end
    end
    return true
end

local function ApplyTexCoordCrop(texture, zoom, cropAR)
    if not texture then return end
    zoom = zoom or 0.08
    cropAR = cropAR or 1.0
    local baseU1, baseU2 = zoom, 1 - zoom
    local baseV1, baseV2 = zoom, 1 - zoom
    local hSize = baseU2 - baseU1
    local vSize = baseV2 - baseV1
    if cropAR < 1.0 then
        local desiredH = vSize * cropAR
        local diff = hSize - desiredH
        baseU1 = baseU1 + (diff / 2)
        baseU2 = baseU2 - (diff / 2)
    elseif cropAR > 1.0 then
        local desiredV = hSize / cropAR
        local diff = vSize - desiredV
        baseV1 = baseV1 + (diff / 2)
        baseV2 = baseV2 - (diff / 2)
    end
    texture:SetTexCoord(baseU1, baseU2, baseV1, baseV2)
end

-- ============================================================
-- [FIX] Forward declarations — ProcessDirtyContainers에서 사용하는 변수
-- ============================================================
local GROUP_VIEWER_MAP  -- 정의: 아래 "그룹 이름 → 소속 뷰어 매핑" 섹션
local GetViewerSettings  -- 정의: 아래 ViewerLayout 헬퍼 함수 섹션

-- ============================================================
-- [FIX] Ayije 패턴: OnUpdate 기반 dirty 컨테이너 배치 레이아웃
-- C_Timer.After(0.03) 대신 OnUpdate로 다음 프레임에 한 번만 처리
-- ============================================================
local dirtyContainers = setmetatable({}, { __mode = "k" }) -- weak-key: GC 시 자동 정리
local dirtyProcessorActive = false
local dirtyProcessorFrame = CreateFrame("Frame")

local function ProcessDirtyContainers(self)
    dirtyProcessorActive = false
    self:SetScript("OnUpdate", nil)

    for container in pairs(dirtyContainers) do
        dirtyContainers[container] = nil
        if container and container._isDDContainer then
            local gn = container._groupName
            if gn then
                local vn = GROUP_VIEWER_MAP[gn]
                local vSettings = GetViewerSettings(vn)
                if vSettings then
                    GroupRenderer:LayoutGroup(container, vSettings, vn)
                end
            end
            -- 모든 아이콘이 숨겨졌으면 그룹 프레임도 숨기기
            local anyVis = false
            for i = 1, (container._iconCount or 0) do
                local ic = container._managedIcons[i]
                if ic and ic:IsShown() then anyVis = true; break end
            end
            if not anyVis then
                container:Hide()
                if DDingUI.ContainerSync then
                    DDingUI.ContainerSync:SyncAll()
                end
            end
        end
    end
end

function GroupRenderer:MarkContainerDirty(container)
    if not container then return end
    dirtyContainers[container] = true
    if not dirtyProcessorActive then
        dirtyProcessorActive = true
        dirtyProcessorFrame:SetScript("OnUpdate", ProcessDirtyContainers)
    end
end

-- ============================================================
-- [REPARENT] 그룹 이름 → 소속 뷰어 매핑
-- CDM 3대 그룹은 실제 뷰어, 커스텀 그룹은 가상 뷰어 사용
-- ============================================================

GROUP_VIEWER_MAP = {
    ["Cooldowns"] = "EssentialCooldownViewer",
    ["Buffs"]     = "BuffIconCooldownViewer",
    ["Utility"]   = "UtilityCooldownViewer",
}

-- [FIX] 커스텀 그룹용 가상 뷰어 등록 — CDM과 동일한 경로(GetViewerSettings 등) 사용
function GroupRenderer:RegisterVirtualViewer(groupName)
    if GROUP_VIEWER_MAP[groupName] then return end -- 이미 등록됨
    local virtualName = "DDingUI_VV_" .. groupName
    GROUP_VIEWER_MAP[groupName] = virtualName
end

function GroupRenderer:UnregisterVirtualViewer(groupName)
    local existing = GROUP_VIEWER_MAP[groupName]
    if existing and existing:match("^DDingUI_VV_") then
        GROUP_VIEWER_MAP[groupName] = nil
    end
end

-- [FIX] 커스텀 그룹 설정 → profile.viewers[virtualViewer]에 동기화
-- GS_Range의 VIEWER_REDIRECT_KEYS가 읽고 쓰는 위치와 동일
local SYNC_KEYS = { "iconSize", "spacing", "aspectRatioCrop", "rowLimit",
    "primaryDirection", "secondaryDirection", "rowIconSizes",
    "borderSize", "zoom", "groupAlpha" }

function GroupRenderer:SyncGroupToViewer(groupName, groupSettings)
    local viewerName = GROUP_VIEWER_MAP[groupName]
    if not viewerName or not viewerName:match("^DDingUI_VV_") then return end
    local profile = DDingUI.db and DDingUI.db.profile
    if not profile then return end
    profile.viewers = profile.viewers or {}
    local vs = profile.viewers[viewerName]
    if not vs then
        vs = {}
        profile.viewers[viewerName] = vs
    end
    for _, key in ipairs(SYNC_KEYS) do
        vs[key] = groupSettings[key]
    end
    -- direction → primaryDirection 변환
    if groupSettings.direction and not groupSettings.primaryDirection then
        vs.primaryDirection = groupSettings.direction
    end
    if groupSettings.growDirection and not groupSettings.secondaryDirection then
        vs.secondaryDirection = groupSettings.growDirection
    end
end

-- ============================================================
-- ViewerLayout 동일 헬퍼 함수들
-- [REPARENT] 뷰어 설정을 100% 반영하기 위해 ViewerLayout과 동일 로직 복제
-- ============================================================

local function PixelSnap(val)
    return math_floor(val + 0.5)
end

-- profile.viewers[viewerName] 참조 (forward-declared at top)
GetViewerSettings = function(viewerName)
    local profile = DDingUI.db and DDingUI.db.profile
    return viewerName and profile and profile.viewers and profile.viewers[viewerName]
end

-- ViewerLayout.ComputeIconDimensions 동일
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

    return PixelSnap(iconWidth), PixelSnap(iconHeight)
end

-- [FIX] spacing 값 그대로 사용 (ViewerLayout과 동일)
local function ComputeSpacing(settings)
    local spacing = settings.spacing or 2
    return PixelSnap(spacing)
end

-- ViewerLayout.GetRowIconSize 동일
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

-- ViewerLayout.DIRECTION_RULES 동일
local DIRECTION_RULES = {
    CENTERED_HORIZONTAL = { type = "HORIZONTAL", defaultSecondary = "DOWN",  allowed = { UP = true, DOWN = true } },
    LEFT                = { type = "HORIZONTAL", defaultSecondary = "DOWN",  allowed = { UP = true, DOWN = true } },
    RIGHT               = { type = "HORIZONTAL", defaultSecondary = "DOWN",  allowed = { UP = true, DOWN = true } },
    UP                  = { type = "VERTICAL",   defaultSecondary = "RIGHT", allowed = { LEFT = true, RIGHT = true } },
    DOWN                = { type = "VERTICAL",   defaultSecondary = "RIGHT", allowed = { LEFT = true, RIGHT = true } },
    STATIC              = { type = "STATIC" },
}

-- ViewerLayout.NormalizeDirectionToken 동일
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

-- ViewerLayout.ResolveDirections 동일
local function ResolveDirections(viewerName, settings)
    local primary = NormalizeDirectionToken(settings.primaryDirection)
    local secondary = NormalizeDirectionToken(settings.secondaryDirection)

    -- Legacy growthDirection 호환
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

    -- BuffIconCooldownViewer rowGrowDirection 호환
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

    local rowLimit = settings.rowLimit or 0
    if rowLimit < 0 then rowLimit = 0 end
    rowLimit = math_floor(rowLimit + 0.0001)

    if rule.type ~= "STATIC" and rowLimit > 0 then
        if not secondary or not rule.allowed[secondary] then
            secondary = rule.defaultSecondary
        end
    else
        secondary = nil
    end

    return primary, secondary, rowLimit, rule.type
end

-- ============================================================
-- snap-back 안전 아이콘 위치/크기 설정
-- FrameController 훅을 우회하면서 타겟 값도 동시 갱신
-- ============================================================

local function SetIconPosition(icon, container, x, y)
    -- 위치 동일하면 skip → ClearAllPoints 깜빡임 방지
    -- [REPARENT] GetParent() → _ddContainerRef (parent는 UIParent)
    if icon._ddTargetPoint == "CENTER"
       and icon._ddTargetX == x and icon._ddTargetY == y
       and icon._ddContainerRef == container then
        return
    end

    icon._ddTargetPoint = "CENTER"
    icon._ddTargetRelPoint = "CENTER"
    icon._ddTargetX = x
    icon._ddTargetY = y

    icon._ddSettingPosition = true
    icon:ClearAllPoints()
    icon:SetPoint("CENTER", container, "CENTER", x, y)
    icon._ddSettingPosition = false
end

local function SetIconSize(icon, w, h)
    -- 크기 동일하면 skip
    if icon._ddTargetWidth == w and icon._ddTargetHeight == h then return end
    icon._ddTargetWidth = w
    icon._ddTargetHeight = h

    icon._ddSettingSize = true
    icon:SetSize(w, h)
    icon._ddSettingSize = false
end

-- ============================================================
-- ViewerLayout.LayoutHorizontal 동일 (snap-back 지원 버전)
-- CENTERED_HORIZONTAL, LEFT, RIGHT + 보조 방향 UP/DOWN
-- ============================================================

local function LayoutHorizontal(icons, container, primary, secondary, spacing, rowLimit, getDimensionsForRow)
    local count = #icons
    if count == 0 then return 0, 0 end

    local iconsPerRow = rowLimit > 0 and math_max(1, rowLimit) or count
    local numRows = math_ceil(count / iconsPerRow)
    local rowDirection = (secondary == "UP") and 1 or -1

    -- 행 메타데이터 계산
    local rowMeta = {}
    local maxRowWidth = 0
    local totalHeight = 0
    for row = 1, numRows do
        local iconWidth, iconHeight = getDimensionsForRow(row)
        local rowStart = (row - 1) * iconsPerRow + 1
        local rowEnd = math_min(row * iconsPerRow, count)
        local rowCount = rowEnd - rowStart + 1
        local rowWidth = rowCount * iconWidth + (rowCount - 1) * spacing
        if rowWidth < iconWidth then
            rowWidth = iconWidth
        end
        maxRowWidth = math_max(maxRowWidth, rowWidth)
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

    -- Row 1을 기준점으로 anchorY 계산 (DOWN이면 위에서, UP이면 아래에서 시작)
    local anchorY
    if rowDirection == -1 then
        anchorY = (totalHeight / 2) - (rowMeta[1].iconHeight / 2)
    else
        anchorY = -(totalHeight / 2) + (rowMeta[1].iconHeight / 2)
    end

    local currentY = anchorY
    for row = 1, numRows do
        local meta = rowMeta[row]
        local baseX
        if primary == "CENTERED_HORIZONTAL" then
            -- 각 행이 독립적으로 가운데 정렬 (행별 아이콘 수에 맞춤)
            baseX = -meta.width / 2 + meta.iconWidth / 2
        elseif primary == "RIGHT" then
            baseX = -(maxRowWidth / 2) + (meta.iconWidth / 2)
        else -- LEFT
            baseX = (maxRowWidth / 2) - (meta.iconWidth / 2)
        end

        for position = 0, meta.count - 1 do
            local icon = icons[meta.startIndex + position]
            local x
            if primary == "LEFT" then
                x = baseX - position * (meta.iconWidth + spacing)
            else
                x = baseX + position * (meta.iconWidth + spacing)
            end

            SetIconSize(icon, meta.iconWidth, meta.iconHeight)
            SetIconPosition(icon, container, math_floor(x + 0.5), math_floor(currentY + 0.5))
        end

        local nextMeta = rowMeta[row + 1]
        if nextMeta then
            local step = (meta.iconHeight / 2) + (nextMeta.iconHeight / 2) + spacing
            currentY = currentY + step * rowDirection
        end
    end

    return maxRowWidth, totalHeight
end

-- ============================================================
-- ViewerLayout.LayoutVertical 동일 (snap-back 지원 버전)
-- UP, DOWN + 보조 방향 LEFT/RIGHT
-- ============================================================

local function LayoutVertical(icons, container, primary, secondary, spacing, rowLimit, getDimensionsForRow)
    local count = #icons
    if count == 0 then return 0, 0 end

    local iconsPerColumn = rowLimit > 0 and math_max(1, rowLimit) or count
    local numColumns = math_ceil(count / iconsPerColumn)
    local columnDirection = (secondary == "LEFT") and -1 or 1
    local verticalDirection = (primary == "UP") and 1 or -1

    -- 열 메타데이터 계산
    local columnMeta = {}
    local maxColumnHeight = 0
    local totalWidth = 0
    for column = 1, numColumns do
        local iconWidth, iconHeight = getDimensionsForRow(column)
        local columnStart = (column - 1) * iconsPerColumn + 1
        local columnEnd = math_min(column * iconsPerColumn, count)
        local columnCount = columnEnd - columnStart + 1
        local columnHeight = columnCount * iconHeight + (columnCount - 1) * spacing

        maxColumnHeight = math_max(maxColumnHeight, columnHeight)
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

    -- Column 1 기준 anchorX
    local anchorX
    if columnDirection == 1 then
        anchorX = -(totalWidth / 2) + (columnMeta[1].iconWidth / 2)
    else
        anchorX = (totalWidth / 2) - (columnMeta[1].iconWidth / 2)
    end

    -- 수직 기준 anchorY
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

            SetIconSize(icon, meta.iconWidth, meta.iconHeight)
            SetIconPosition(icon, container, math_floor(currentX + 0.5), math_floor(y + 0.5))
        end

        local nextMeta = columnMeta[column + 1]
        if nextMeta then
            local step = (meta.iconWidth / 2) + (nextMeta.iconWidth / 2) + spacing
            currentX = currentX + step * columnDirection
        end
    end

    return totalWidth, totalHeight
end

-- ============================================================
-- 그룹 프레임 생성
-- [REPARENT] _isDDContainer 태그 추가
-- ============================================================

function GroupRenderer:CreateGroupFrame(groupName, groupSettings)
    if self.groupFrames[groupName] then
        return self.groupFrames[groupName]
    end

    local frame = CreateFrame("Frame", "DDingUI_Group_" .. groupName, UIParent)
    frame:SetSize(200, 50) -- 초기 크기, 레이아웃 후 조정

    -- [REPARENT] Mover 저장 위치가 없으면 소속 CDM 뷰어 위치를 마이그레이션
    -- [FIX] _moverSaved 플래그: 편집모드에서 위치 저장 시 설정됨
    -- → 뷰어 마이그레이션을 건너뛰고 저장된 groupSettings 위치 사용

    -- [FIX] 핵심 3대 그룹은 프록시 앵커가 마스터 → 프록시 위치에서 초기 좌표 설정
    -- SyncProxyAnchors OnUpdate에서 매 프레임 프록시→그룹 동기화하므로
    -- 여기서는 프록시가 있으면 프록시에 맞추고, 없으면 settings 폴백
    local CORE_PROXY = {
        ["Cooldowns"] = "DDingUI_Anchor_Cooldowns",
        ["Buffs"]     = "DDingUI_Anchor_Buffs",
        ["Utility"]   = "DDingUI_Anchor_Utility",
    }
    local proxyName = CORE_PROXY[groupName]
    local proxyFrame = proxyName and _G[proxyName]
    
    local moverId = proxyName or ("DDingUI_Group_" .. groupName)
    local hasMoverPos = DDingUI.Movers and DDingUI.Movers.CreatedMovers
        and DDingUI.Movers.CreatedMovers[moverId]
    local hasSavedPos = groupSettings._moverSaved  -- [FIX] 편집모드 저장 위치 존재 여부
    local hasBeenMigrated = groupSettings._viewerPosMigrated  -- [FIX] 이미 마이그레이션 완료된 프로필
    local usedViewerPos = false

    -- [FIX] 프록시 앵커가 있는 핵심 3대 그룹은 별도의 폴백이나 좌표계산 없이 프록시를 앵커로 종속됨.
    -- 프록시 자체의 위치는 Mover에서 groupSettings 정보를 읽어 완벽히 복원하므로, 
    -- 0,0으로 맞추기만 하면 항상 정확히 일치하며 마우스 드래그도 실시간으로 반영됨.
    if proxyFrame then
        frame:SetPoint("CENTER", proxyFrame, "CENTER", 0, 0)
    else
        if not hasMoverPos and not hasSavedPos and not hasBeenMigrated then
            local viewerName = GROUP_VIEWER_MAP[groupName]
            local profile = DDingUI.db and DDingUI.db.profile
            local vs = viewerName and profile and profile.viewers and profile.viewers[viewerName]

            -- [FIX] 뷰어가 구 프로필에서 비활성이었으면 뷰어 위치 마이그레이션 스킵
            local viewerWasDisabled = vs and vs.enabled == false

            -- 1순위: 뷰어 프로필의 커스텀 앵커 프레임
            if not viewerWasDisabled and vs and vs.anchorFrame and vs.anchorFrame ~= "" then
                local target = _G[vs.anchorFrame]
                if target then
                    local pt = vs.anchorPoint or "CENTER"
                    local ox = vs.anchorOffsetX or 0
                    local oy = vs.anchorOffsetY or 0
                    frame:SetPoint(pt, target, pt, ox, oy)
                    groupSettings.attachTo = vs.anchorFrame
                    groupSettings.anchorPoint = pt
                    groupSettings.selfPoint = pt
                    groupSettings.offsetX = ox
                    groupSettings.offsetY = oy
                    groupSettings._moverSaved = true
                    usedViewerPos = true
                end
            end

            -- 2순위: 뷰어 프로필의 앵커 오프셋
            if not usedViewerPos and not viewerWasDisabled and vs then
                local ox = vs.anchorOffsetX or 0
                local oy = vs.anchorOffsetY or 0
                if ox ~= 0 or oy ~= 0 then
                    local pt = vs.anchorPoint or "CENTER"
                    frame:SetPoint(pt, UIParent, pt, ox, oy)
                    groupSettings.anchorPoint = pt
                    groupSettings.selfPoint = pt
                    groupSettings.offsetX = ox
                    groupSettings.offsetY = oy
                    groupSettings._moverSaved = true
                    usedViewerPos = true
                end
            end

            -- 2.5순위: movers 테이블에서 뷰어 이름으로 저장된 위치
            if not usedViewerPos and not viewerWasDisabled then
                local movers = profile and profile.movers
                local moverStr = viewerName and movers and movers[viewerName]
                if moverStr and type(moverStr) == "string" then
                    local pt, relFrame, relPt, sx, sy = strsplit(",", moverStr)
                    local mx, my = tonumber(sx), tonumber(sy)
                    if mx and my then
                        pt = pt or "CENTER"
                        relPt = relPt or "CENTER"
                        local anchor = (relFrame and relFrame ~= "" and _G[relFrame]) or UIParent
                        frame:SetPoint(pt, anchor, relPt, mx, my)
                        groupSettings.anchorPoint = relPt
                        groupSettings.selfPoint = pt
                        groupSettings.offsetX = mx
                        groupSettings.offsetY = my
                        if relFrame and relFrame ~= "" and relFrame ~= "UIParent" then
                            groupSettings.attachTo = relFrame
                        end
                        groupSettings._moverSaved = true
                        usedViewerPos = true
                    end
                end
            end

            -- 3순위: CDM 편집모드 DB 직접 읽기 (Ayije_CDM.db.editModePositions)
            -- CDM이 뷰어 위치를 DB에 저장하므로, 프레임 위치 대신 DB에서 직접 읽으면 타이밍 문제 없음
            if not usedViewerPos and not viewerWasDisabled then
                local CDM_Addon = _G["Ayije_CDM"]
                local cdmDB = CDM_Addon and CDM_Addon.db
                local editPos = cdmDB and cdmDB.editModePositions
                if editPos then
                    local viewerPos = editPos[viewerName]
                    local savedPos = viewerPos and viewerPos["Default"]
                    if savedPos and savedPos.x and savedPos.y then
                        local pt = savedPos.point or "CENTER"
                        local sx = savedPos.x
                        local sy = savedPos.y
                        -- Essential/Buffs: AnchorMainLayoutContainer는 TOP/BOTTOM 기준
                        -- Essential: SetPixelPerfectPoint(container, "TOP", UIParent, point, x, y)
                        -- Buffs: SetPixelPerfectPoint(container, "BOTTOM", UIParent, point, x, y + yOffset)
                        -- DDingUI 그룹 시스템은 CENTER 기준이므로 변환 필요 없이 그대로 사용
                        frame:SetPoint("CENTER", UIParent, pt, sx, sy)
                        groupSettings.anchorPoint = pt
                        groupSettings.selfPoint = "CENTER"
                        groupSettings.offsetX = sx
                        groupSettings.offsetY = sy
                        groupSettings._moverSaved = true
                        usedViewerPos = true
                    end
                end
            end

            -- [FALLBACK] CDM DB도 없으면 → 지연 재시도 (GetCenter 폴백)
            if not usedViewerPos and not viewerWasDisabled and viewerName then
                local capturedFrame = frame
                local capturedSettings = groupSettings
                local capturedViewerName = viewerName
                local retryDelays = { 2, 4 }
                for _, delay in ipairs(retryDelays) do
                    C_Timer.After(delay, function()
                        if capturedSettings._moverSaved then return end
                        local viewer = _G[capturedViewerName]
                        if not viewer then return end
                        local cx, cy = viewer:GetCenter()
                        local uiCX, uiCY = UIParent:GetCenter()
                        if cx and cy and uiCX and uiCY then
                            local ox = cx - uiCX
                            local oy = cy - uiCY
                            if math.abs(ox) > 50 or math.abs(oy) > 50 then
                                capturedSettings.anchorPoint = "CENTER"
                                capturedSettings.selfPoint = "CENTER"
                                capturedSettings.offsetX = ox
                                capturedSettings.offsetY = oy
                                capturedSettings._moverSaved = true
                                capturedFrame:ClearAllPoints()
                                capturedFrame:SetPoint("CENTER", UIParent, "CENTER", ox, oy)
                            end
                        end
                    end)
                end
            end
        end

        local attachTo = groupSettings.attachTo or "UIParent"
        local anchorFrame = _G[attachTo] or UIParent
        local selfPoint = groupSettings.selfPoint or "CENTER"
        frame:SetPoint(
            selfPoint,
            anchorFrame,
            groupSettings.anchorPoint or "CENTER",
            groupSettings.offsetX or 0,
            groupSettings.offsetY or 0
        )
    end

    frame:SetFrameStrata("MEDIUM")
    frame:Show()

    frame._groupName = groupName
    frame._isDDContainer = true  -- [REPARENT] FrameController snap-back 훅 식별 태그
    frame._managedIcons = {}     -- 현재 re-parent된 CDM 아이콘 목록
    frame._iconCount = 0

    -- [REPARENT] 컨테이너 OnHide/OnShow → 관리 아이콘 visibility 동기화
    -- UIParent 자식 아이콘은 컨테이너 숨김을 상속하지 않으므로 수동 전파 필요
    frame:HookScript("OnHide", function(self)
        for i = 1, (self._iconCount or 0) do
            local ic = self._managedIcons[i]
            if ic and ic._ddIsManaged then
                ic:Hide()
            end
        end
    end)
    frame:HookScript("OnShow", function(self)
        for i = 1, (self._iconCount or 0) do
            local ic = self._managedIcons[i]
            -- [FIX] _ddingHidden 아이콘은 Show하지 않음 (BuffTrackerBar 추적 중)
            if ic and ic._ddIsManaged and not ic._ddingHidden then
                ic:Show()
            end
        end
    end)

    self.groupFrames[groupName] = frame
    return frame
end

-- ============================================================
-- 그룹 업데이트 (CDM 아이콘 SetParent)
-- [REPARENT] 뷰어 설정 100% 반영 — iconSize, spacing, direction, border 등 전부
-- ============================================================

function GroupRenderer:UpdateGroup(groupName, iconList, groupSettings)
    local frame = self.groupFrames[groupName]
    if not frame then
        frame = self:CreateGroupFrame(groupName, groupSettings)
    end

    if not groupSettings.enabled then
        self:ReleaseGroupIcons(frame)
        frame:Hide()
        return
    end

    -- 이제 GroupManager:ClassifyIcon에서 원본 CDM 아이콘 자체를 분류해주므로
    -- 다이나믹 아이콘 생성/스킵 등의 이중 로직이 필요 없습니다. (네이티브 하이재킹)
    local newSet = {}
    local combinedList = {}

    for i, entry in ipairs(iconList) do
        if entry.icon then
            newSet[entry.icon] = true
            entry.isCDM = true
            combinedList[#combinedList + 1] = entry
        end
    end
    for _, icon in pairs(frame._managedIcons) do
        if icon and not newSet[icon] then
            if icon._ddIconKey then
                local fc = GetFC()
                if fc and fc.ReleaseFrameFromContainer then
                    fc:ReleaseFrameFromContainer(icon)
                    icon:Hide()
                end
            else
                local fc = GetFC()
                if fc then
                    fc:ReleaseFrameFromContainer(icon)
                end
            end
        end
    end
    wipe(frame._managedIcons)

    local fc = GetFC()

    -- [REPARENT] 뷰어 설정 resolve — 모든 레이아웃/스키닝 파라미터의 원천
    local viewerName = GROUP_VIEWER_MAP[groupName]
    local vs = GetViewerSettings(viewerName)

    -- 기본 아이콘 크기 계산 (뷰어 설정 기반, 없으면 groupSettings fallback)
    local baseIconW, baseIconH
    if vs then
        baseIconW, baseIconH = ComputeIconDimensions(vs)
    else
        local fallback = groupSettings.iconSize or 32
        baseIconW, baseIconH = fallback, fallback
    end

    -- [REPARENT] 스키닝용 프로필 참조 (미리 resolve)
    local IconViewers = DDingUI.IconViewers
    local profile = DDingUI.db and DDingUI.db.profile
    local viewers = profile and profile.viewers

    -- [REPARENT] 1단계: SetupFrameInContainer + SkinIcon (텍스처/테두리/글로우)
    -- SkinIcon이 LayoutGroup보다 먼저 실행 → LayoutGroup이 최종 크기 결정 (rowIconSizes 보존)
    local idx = 0
    for i, entry in ipairs(combinedList) do
        local icon = entry.icon

        if icon then
            local iconData = nil
            if groupSettings.groupType == "dynamic" and groupSettings.sourceGroupKey then
                local dynDB = GetDynamicDB()
                local sourceGroup = dynDB and dynDB.groups[groupSettings.sourceGroupKey]
                if sourceGroup and sourceGroup.icons then
                    for _, iconKey in ipairs(sourceGroup.icons) do
                        local data = dynDB.iconData[iconKey]
                        if data and (data.id == entry.cooldownID or data.spellName == entry.spellName) then
                            iconData = data
                            break
                        end
                    end
                end
            end

            if fc then
                local alreadyManaged = icon._ddIsManaged and icon._ddContainerRef == frame
                    and not GroupRenderer._forceFullSetup
                if not alreadyManaged then
                    fc:SetupFrameInContainer(icon, frame, baseIconW, baseIconH, entry.cooldownID)

                    if iconData then
                        -- [다이나믹 아이콘 스키닝]
                        -- 1) 그룹 전체 옵션 적용 (폰트, 배경, 공통 두께 등)
                        if IconViewers and IconViewers.SkinIcon then
                            pcall(IconViewers.SkinIcon, IconViewers, icon, groupSettings)
                        end

                        -- 2) 개별 아이콘 설정(Aura 디자이너) 오버라이드
                        if iconData.useCustomTex and iconData.texID then
                            icon.icon:SetTexture(iconData.texID)
                        end
                        if iconData.desaturate then
                            icon.icon:SetDesaturated(true)
                        else
                            icon.icon:SetDesaturated(false)
                        end
                        if iconData.borderColor then
                            if icon.border then
                                icon.border:SetVertexColor(unpack(iconData.borderColor))
                            end
                        end
                    else
                        -- [일반 CDM 아이콘 스키닝]
                        if IconViewers and IconViewers.SkinIcon and entry.cooldownID then
                            local srcViewer = fc:GetIconSource(entry.cooldownID)
                            if srcViewer then
                                icon._ddSourceViewer = srcViewer
                            end
                            local skinSettings = srcViewer and viewers and viewers[srcViewer]
                            if skinSettings then
                                pcall(IconViewers.SkinIcon, IconViewers, icon, skinSettings)
                            end
                        end
                    end
                else
                    icon._ddLastCooldownID = entry.cooldownID
                    if iconData and icon.icon then
                        ApplyTexCoordCrop(icon.icon, groupSettings.zoom, groupSettings.aspectRatioCrop)
                    end
                end
                idx = idx + 1
                frame._managedIcons[idx] = icon
            end

            -- [FIX] OnHide → dirty 컨테이너 등록 (C_Timer.After 제거, OnUpdate 배치 처리)
            if not icon._ddLayoutHooked then
                icon._ddLayoutHooked = true
                icon:HookScript("OnHide", function(self)
                    if not self._ddIsManaged then return end
                    local p = self._ddContainerRef
                    if not (p and p._isDDContainer and p._groupName) then return end
                    GroupRenderer:MarkContainerDirty(p)
                end)
            end
        end
    end
    frame._iconCount = idx

    -- [REPARENT] viewerSettings fallback: 뷰어 매핑 없는 그룹은 groupSettings 사용
    if not vs then
        -- [REPARENT] 기본 뷰어 매핑 그룹은 뷰어 기본값(CENTERED_HORIZONTAL, rowLimit=0) 사용
        -- groupSettings.rowLimit은 migration 레거시(12) → 의도치 않은 두 줄 방지
        local isDefaultViewer = GROUP_VIEWER_MAP[groupName] ~= nil
        vs = {
            iconSize = groupSettings.iconSize or 32,
            aspectRatioCrop = groupSettings.aspectRatioCrop or 1.0,
            spacing = groupSettings.spacing or 2,
            primaryDirection = isDefaultViewer and "CENTERED_HORIZONTAL" or groupSettings.direction,
            secondaryDirection = isDefaultViewer and nil or groupSettings.growDirection,
            rowLimit = isDefaultViewer and 0 or (groupSettings.rowLimit or 0),
            rowIconSizes = groupSettings.rowIconSizes,
        }
    end

    -- [REPARENT] 2단계: LayoutGroup (최종 크기/위치 결정 — rowIconSizes 반영)
    -- SkinIcon이 설정한 크기를 LayoutGroup이 덮어씀 → rowIconSizes 정상 동작
    self:LayoutGroup(frame, vs, viewerName)

    if idx > 0 then
        -- [FIX] CDM 뷰어의 IsShown() 반영 (전투 외 버프 숨김 등)
        -- ContainerSync는 alpha=0만 설정 → CDM의 Show/Hide는 그대로 유지
        -- 뷰어가 CDM에 의해 숨겨진 상태면 아이콘만 숨김 (프레임은 유지 — 앵커 보존)
        local sourceViewer = viewerName and _G[viewerName]
        if sourceViewer and not sourceViewer:IsShown() then
            -- [FIX] 프레임 자체는 숨기지 않음 — 앵커 체인 보존
            for i = 1, idx do
                local ic = frame._managedIcons[i]
                if ic then ic:Hide() end
            end
        else
            frame:Show()
        end
    else
        -- [FIX] 아이콘 0개여도 프레임을 숨기지 않음
        -- 숨기면 이 그룹에 앵커된 프레임들의 앵커가 끊어져 엘레베이터 현상 발생
        -- 프레임은 비어있지만 :IsShown()=true 유지 → 앵커 체인 보존
        frame:Show()
    end

    -- [12.0.1] 그룹 아이콘 투명도 적용
    -- [FIX] FlightHide 활성 또는 페이드 중이면 alpha=0 유지 (Reconcile이 덮어쓰는 것 방지)
    local fh = DDingUI.FlightHide
    local flightHiding = fh and (fh.isActive or fh._hiding)
    local groupAlpha = flightHiding and 0 or (groupSettings.groupAlpha or 1.0)

    -- [FIX] 비행 중 컨테이너 프레임 자체 알파도 0으로 (FlightHide OnUpdate가 alpha=0 도달 후 재적용 안 하므로)
    if flightHiding then
        frame:SetAlpha(0)
    else
        frame:SetAlpha(groupSettings.groupAlpha or 1.0)
    end

    for i = 1, idx do
        local ic = frame._managedIcons[i]
        if ic then
            -- [FIX] BuffTrackerBar가 _ddingHidden으로 숨긴 아이콘은 alpha 유지 (깜빡임 방지)
            if not ic._ddingHidden then
                ic:SetAlpha(groupAlpha)
            end
        end
    end
end

-- ============================================================
-- [FIX] 편집모드 팬텀 크기 계산
-- 그룹의 전체 아이콘 수 × 레이아웃 설정으로 LayoutGroup과 동일한 크기 산출
-- ============================================================
function GroupRenderer:ComputeEditModeSize(groupName)
    local gsDB = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.groupSystem
    if not gsDB or not gsDB.groups then return nil, nil end
    local grpCfg = gsDB.groups[groupName]
    if not grpCfg then return nil, nil end

    -- 1. 총 아이콘 수 계산 (CDM 할당 + 동적 아이콘)
    local totalIcons = 0
    -- CDM spellAssignments
    if gsDB.spellAssignments then
        for _, grp in pairs(gsDB.spellAssignments) do
            if grp == groupName then
                totalIcons = totalIcons + 1
            end
        end
    end
    -- 동적 아이콘 (CustomIcons)
    local sourceKey = grpCfg.sourceGroupKey
    if sourceKey then
        local dynDB = DDingUI.db.profile.dynamicIcons
        local dynGroup = dynDB and dynDB.groups and dynDB.groups[sourceKey]
        if dynGroup and dynGroup.icons then
            totalIcons = totalIcons + #dynGroup.icons
        end
    end

    if totalIcons <= 0 then return nil, nil end

    -- 2. 뷰어 설정 구성 (그룹 설정에서 레이아웃 관련 필드 수집)
    local vs = {}
    vs.iconSize = grpCfg.iconSize or 32
    vs.spacing = grpCfg.spacing or 2
    vs.rowLimit = grpCfg.rowLimit or 0
    vs.primaryDirection = grpCfg.primaryDirection or "CENTERED_HORIZONTAL"
    vs.secondaryDirection = grpCfg.secondaryDirection
    vs.growthDirection = grpCfg.growthDirection
    -- 종횡비: 숫자(aspectRatioCrop) 또는 문자열("W:H" 형태)
    if grpCfg.aspectRatioCrop then
        vs.aspectRatioCrop = grpCfg.aspectRatioCrop
    elseif grpCfg.aspectRatio then
        vs.aspectRatio = grpCfg.aspectRatio
    end

    -- 3. 아이콘 크기 계산 (종횡비 반영)
    local iconW, iconH = ComputeIconDimensions(vs)
    local spacing = ComputeSpacing(vs)

    -- 4. 방향 및 rowLimit
    local _, _, rowLimit, layoutType = ResolveDirections(nil, vs)
    if rowLimit <= 0 then rowLimit = totalIcons end

    -- 5. 행/열 계산
    local rows = math.ceil(totalIcons / rowLimit)
    local cols = math.min(totalIcons, rowLimit)

    -- 6. 전체 크기 (VERTICAL이면 가로/세로 스왑)
    local w, h
    if layoutType == "VERTICAL" then
        w = rows * iconW + math.max(rows - 1, 0) * spacing
        h = cols * iconH + math.max(cols - 1, 0) * spacing
    else
        w = cols * iconW + math.max(cols - 1, 0) * spacing
        h = rows * iconH + math.max(rows - 1, 0) * spacing
    end

    return math.max(math.floor(w + 0.5), 1), math.max(math.floor(h + 0.5), 1)
end

-- ============================================================
-- 레이아웃 엔진
-- [REPARENT] ViewerLayout과 동일 — 뷰어 설정의 direction, spacing,
-- rowLimit, rowIconSizes, iconSize, aspectRatioCrop 전부 반영
-- CENTER 앵커 기반 + snap-back 타겟 자동 설정
-- ============================================================

function GroupRenderer:LayoutGroup(frame, viewerSettings, viewerName)
    if not frame or not frame._managedIcons then return end

    -- [FIX] CDM 뷰어가 숨겨진 상태 → LayoutGroup 스킵
    -- 아이콘만 Hide하고 프레임 크기는 변경하지 않으면
    -- 앵커된 다른 그룹의 위치가 유지됨 (엘레베이터 방지)
    --
    -- [FIX] _viewerHidden 고착 방지: 뷰어 재생성 시 OnShow 훅이 새 객체에
    -- 미설치되어 플래그가 true로 고착될 수 있음. 실제 뷰어 상태를 확인하여 보정.
    if frame._viewerHidden then
        local actualViewer = viewerName and _G[viewerName]
        if actualViewer and actualViewer:IsShown() then
            -- 뷰어가 실제로 보이는데 플래그가 true → 고착 상태 → 해제
            frame._viewerHidden = false
        else
            return
        end
    end

    -- [REPARENT] 보이는 아이콘만 레이아웃에 포함 (belt-and-suspenders)
    -- CDM이 Hide()한 아이콘이 _managedIcons에 남아있으면 빈 공간("이 빠짐") 발생
    -- [FIX] _ddingHidden 아이콘도 제외: BuffTrackerBar가 추적 중인 버프를 CDM에서
    -- 완전히 빼서 정렬 공백 없이 나머지 아이콘이 올바르게 배치되도록 함
    local allIcons = frame._managedIcons
    local icons = {}
    local count = 0
    for i = 1, (frame._iconCount or 0) do
        local icon = allIcons[i]
        if icon and icon:IsShown() and not icon._ddingHidden then
            count = count + 1
            icons[count] = icon
        end
    end
    -- [FIX] 가상 최소 크기 계산 (핵심 3대 그룹만: Cooldowns, Buffs, Utility)
    -- 다이나믹 그룹은 다른 모듈이 앵커되지 않으므로 phantom 불필요
    local phantomW, phantomH = 1, 1
    local phantomPrimary, phantomSecondary, phantomLayoutType
    local isCoreGroup = (viewerName == "BuffIconCooldownViewer")  -- 강화효과만 phantom 적용
    if isCoreGroup and viewerSettings then
        local phantomIconW, phantomIconH = ComputeIconDimensions(viewerSettings)
        local phantomSpacing = ComputeSpacing(viewerSettings)
        local phantomRowLimit = viewerSettings.rowLimit or 0
        if phantomRowLimit <= 0 then phantomRowLimit = 9 end
        local phantomRows = (viewerName == "BuffIconCooldownViewer") and 1 or 2
        -- [FIX] ResolveDirections는 rowLimit=0이면 secondary를 nil로 버림
        -- phantom은 2줄 기준이므로, rowLimit을 강제로 2로 설정하여 유저의 secondary 설정을 보존
        local phantomResolveSettings = {}
        for k, v in pairs(viewerSettings) do phantomResolveSettings[k] = v end
        phantomResolveSettings.rowLimit = 2
        phantomPrimary, phantomSecondary, _, phantomLayoutType = ResolveDirections(viewerName, phantomResolveSettings)
        if phantomLayoutType == "VERTICAL" then
            phantomW = phantomRows * phantomIconW + (phantomRows - 1) * phantomSpacing
            phantomH = phantomRowLimit * phantomIconH + (phantomRowLimit - 1) * phantomSpacing
        else
            phantomW = phantomRowLimit * phantomIconW + (phantomRowLimit - 1) * phantomSpacing
            phantomH = phantomRows * phantomIconH + (phantomRows - 1) * phantomSpacing
        end
        phantomW = math_max(PixelSnap(phantomW), 1)
        phantomH = math_max(PixelSnap(phantomH), 1)
    end

    if count == 0 then
        -- [FIX] 편집모드에서 다이나믹 그룹: 등록된 전체 아이콘 수 기반 크기
        local isEditMode = (DDingUI.Movers and DDingUI.Movers.ConfigMode)
            or (EditModeManagerFrame and EditModeManagerFrame:IsEditModeActive())
        if isEditMode and frame._groupName and not isCoreGroup then
            local gsDB = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.groupSystem
            local grpCfg = gsDB and gsDB.groups and gsDB.groups[frame._groupName]
            local sourceKey = grpCfg and grpCfg.sourceGroupKey
            if sourceKey then
                local dynDB = DDingUI.db.profile.dynamicIcons
                local dynGroup = dynDB and dynDB.groups and dynDB.groups[sourceKey]
                local totalIcons = dynGroup and dynGroup.icons and #dynGroup.icons or 0
                if totalIcons > 0 then
                    local vs = viewerSettings or {}
                    local iconW, iconH = ComputeIconDimensions(vs)
                    local spacing = ComputeSpacing(vs)
                    local rowLimit = vs.rowLimit or 0
                    if rowLimit <= 0 then rowLimit = totalIcons end
                    local rows = math.ceil(totalIcons / rowLimit)
                    local cols = math.min(totalIcons, rowLimit)
                    phantomW = math_max(cols * iconW + math.max(cols - 1, 0) * spacing, 1)
                    phantomH = math_max(rows * iconH + math.max(rows - 1, 0) * spacing, 1)
                end
            end
        end
        frame:SetSize(phantomW, phantomH)
        frame._lastLayoutW = phantomW
        frame._lastLayoutH = phantomH
        frame.__cdmIconWidth = phantomW
        return
    end

    -- 뷰어 설정이 없으면 최소 fallback (UpdateGroup에서 이미 처리하지만 안전)
    if not viewerSettings then
        viewerSettings = { iconSize = 32, spacing = 2, primaryDirection = "CENTERED_HORIZONTAL" }
    end

    -- ViewerLayout과 동일하게 방향/행제한 resolve
    local primary, secondary, rowLimit, layoutType = ResolveDirections(viewerName, viewerSettings)

    -- [12.0.1] rowLimit 오버라이드 제거: 뷰어 설정의 rowLimit을 그대로 사용
    -- 기본값 0(=단일행)이므로, 유저가 명시적으로 설정한 값(예: 9)이 존중됨

    local spacing = ComputeSpacing(viewerSettings)

    -- 행/열별 아이콘 크기 (rowIconSizes 지원)
    local rowDimensions = {}
    local function GetDimensionsForRow(rowIndex)
        if not rowDimensions[rowIndex] then
            local overrideSize = GetRowIconSize(viewerSettings, rowIndex)
            local w, h = ComputeIconDimensions(viewerSettings, overrideSize)
            rowDimensions[rowIndex] = { width = w, height = h }
        end
        return rowDimensions[rowIndex].width, rowDimensions[rowIndex].height
    end

    -- 레이아웃 실행
    local totalW, totalH = 0, 0
    if layoutType == "HORIZONTAL" then
        totalW, totalH = LayoutHorizontal(icons, frame, primary, secondary, spacing, rowLimit, GetDimensionsForRow)
    elseif layoutType == "VERTICAL" then
        totalW, totalH = LayoutVertical(icons, frame, primary, secondary, spacing, rowLimit, GetDimensionsForRow)
    else
        -- STATIC: 크기만 설정, 위치는 그대로
        local iconW, iconH = GetDimensionsForRow(1)
        for i, icon in ipairs(icons) do
            SetIconSize(icon, iconW, iconH)
        end
        totalW = iconW
        totalH = iconH
    end

    -- 컨테이너 크기 설정
    local snappedW = math_max(PixelSnap(totalW), 1)
    local snappedH = math_max(PixelSnap(totalH), 1)

    -- [FIX] 가상 최소 크기 적용: 아이콘이 있어도 프레임이 phantom 미만으로 줄어들지 않음
    local finalW = math_max(snappedW, phantomW)
    local finalH = math_max(snappedH, phantomH)

    -- [FIX] 가상 크기가 실제보다 클 때, 아이콘을 방향 설정에 맞게 정렬 (세로 중앙 X)
    -- DOWN → 아이콘을 프레임 상단에 정렬, UP → 하단에 정렬
    if finalH > snappedH then
        local resolvedSecondary = secondary or phantomSecondary or "DOWN"
        local shiftY = 0
        if resolvedSecondary == "UP" then
            -- 아이콘을 프레임 하단에 정렬 (위로 성장)
            shiftY = -(finalH - snappedH) / 2
        else
            -- DOWN 또는 기본: 아이콘을 프레임 상단에 정렬 (아래로 성장)
            shiftY = (finalH - snappedH) / 2
        end
        if shiftY ~= 0 then
            for i = 1, count do
                local icon = icons[i]
                if icon and icon._ddTargetX and icon._ddTargetY then
                    SetIconPosition(icon, frame, icon._ddTargetX, icon._ddTargetY + math_floor(shiftY + 0.5))
                end
            end
        end
    end

    -- [FIX] attachTo 그룹 너비 동기화: 다른 그룹에 앵커된 경우 부모 그룹 너비에 맞춤
    -- 예: Utility가 Cooldowns에 앵커 → Utility 프레임 너비를 Cooldowns와 동일하게
    local groupName = frame._groupName
    if groupName then
        local gs = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.groupSystem
        local groupSettings = gs and gs.groups and gs.groups[groupName]
        if groupSettings then
            local attachTo = groupSettings.attachTo
            if attachTo and attachTo ~= "UIParent" and attachTo ~= "" then
                local parentFrame = _G[attachTo]
                if parentFrame and parentFrame._isDDContainer then
                    local parentW = parentFrame:GetWidth()
                    if parentW and parentW > 1 and parentW > finalW then
                        finalW = parentW
                    end
                end
            end
        end
    end

    frame:SetSize(finalW, finalH)
    frame._lastLayoutW = finalW  -- [FIX] 엘레베이터 방지: count==0일 때 이 크기 유지
    frame._lastLayoutH = finalH

    -- [FIX] 프록시 앵커 크기 즉시 동기화 (OnUpdate 지연 없이)
    -- 아이콘 크기/간격 변경, 프로필 전환 등 모든 경우에 즉시 반영
    -- [FIX] groupName은 L990에서 이미 선언 — 재선언(shadowing) 제거
    local CORE_PROXY_NAMES = {
        ["Cooldowns"] = "DDingUI_Anchor_Cooldowns",
        ["Buffs"]     = "DDingUI_Anchor_Buffs",
        ["Utility"]   = "DDingUI_Anchor_Utility",
    }
    local proxyName = groupName and CORE_PROXY_NAMES[groupName]
    local proxy = proxyName and _G[proxyName]
    if proxy then
        -- [FIX] Reconcile → LayoutGroup 경로가 tainted 일 수 있음
        -- 전투 중 SetSize 호출 시 ADDON_ACTION_BLOCKED 방지
        if InCombatLockdown() then
            -- 전투 종료 후 지연 동기화
            C_Timer.After(0.5, function()
                if proxy and not InCombatLockdown() then
                    proxy:SetSize(finalW, finalH)
                    proxy.__cdmIconWidth = snappedW
                    proxy._lastSyncW = math.floor(finalW + 0.5)
                    proxy._lastSyncH = math.floor(finalH + 0.5)
                end
            end)
        else
            proxy:SetSize(finalW, finalH)
            proxy.__cdmIconWidth = snappedW
            proxy._lastSyncW = math.floor(finalW + 0.5)
            proxy._lastSyncH = math.floor(finalH + 0.5)
        end
    end

    -- [REPARENT] __cdmIconWidth 동기화 (BuffTrackerBar, ResourceBars 등이 참조)
    frame.__cdmIconWidth = snappedW
    -- [FIX] 원본 뷰어에도 미러링 — 리소스바가 뷰어에서 직접 읽으므로
    local viewerFrame = viewerName and _G[viewerName]
    if viewerFrame then
        viewerFrame.__cdmIconWidth = snappedW
    end

    -- [REPARENT] groupOffsets: 파티/레이드 상태별 아이콘 위치 보정
    -- ViewerLayout.GetGroupOffset 동일 로직
    if viewerSettings.groupOffsets then
        local groupOX, groupOY = 0, 0
        if IsInRaid() then
            local r = viewerSettings.groupOffsets.raid
            groupOX = r and r.x or 0
            groupOY = r and r.y or 0
        elseif IsInGroup() then
            local p = viewerSettings.groupOffsets.party
            groupOX = p and p.x or 0
            groupOY = p and p.y or 0
        end

        if groupOX ~= 0 or groupOY ~= 0 then
            if DDingUI.Scale then
                groupOX = DDingUI:Scale(groupOX)
                groupOY = DDingUI:Scale(groupOY)
            end
            for i = 1, count do
                local icon = icons[i]
                if icon and icon._ddTargetX and icon._ddTargetY then
                    SetIconPosition(icon, frame, icon._ddTargetX + groupOX, icon._ddTargetY + groupOY)
                end
            end
        end
    end
end

-- ============================================================
-- 아이콘 복원 (그룹/전체)
-- [REPARENT] FrameController.ReleaseFrameFromContainer 사용
-- ============================================================

function GroupRenderer:ReleaseGroupIcons(frame)
    if not frame or not frame._managedIcons then return end

    local fc = GetFC()
    local bridge = DDingUI.DynamicIconBridge
    
    local iconsToHide = {}
    
    for _, icon in pairs(frame._managedIcons) do
        if icon then
            if icon._ddIconKey then
                -- [FIX] 동적 아이콘: bridge로 해제 + 숨기기
                if icon.Hide then icon:Hide() end
                iconsToHide[#iconsToHide + 1] = icon
                if bridge then bridge:ReleaseFrame(icon, icon._ddIconKey) end
            else
                -- CDM 아이콘
                if fc then
                    fc:ReleaseFrameFromContainer(icon)
                end
            end
        end
    end
    
    -- 동적 아이콘은 Release 후 reparent로 Show될 수 있으므로 다시 Hide
    for _, icon in ipairs(iconsToHide) do
        if icon.Hide then icon:Hide() end
    end
    
    wipe(frame._managedIcons)
    frame._iconCount = 0
end

function GroupRenderer:RestoreAllIcons()
    for groupName, frame in pairs(self.groupFrames) do
        self:ReleaseGroupIcons(frame)
    end
end

-- ============================================================
-- 정리
-- ============================================================

function GroupRenderer:DestroyAllGroups()
    self:RestoreAllIcons()

    for groupName, frame in pairs(self.groupFrames) do
        frame:Hide()
    end
    wipe(self.groupFrames)

    -- [FIX] 프록시 앵커 크기 캐시 초기화
    -- groupFrame 파괴 후 SyncProxyAnchors가 else 분기에서 작은 크기로 오염되는 것 방지
    -- 새 groupFrame 생성 시 크기가 확실히 반영되도록 캐시 리셋
    if DDingUI.ProxyAnchors then
        for _, proxy in pairs(DDingUI.ProxyAnchors) do
            proxy._lastSyncW = nil
            proxy._lastSyncH = nil
        end
    end
end

function GroupRenderer:DestroyGroup(groupName)
    local frame = self.groupFrames[groupName]
    if not frame then return end

    -- [FIX] 동적/CDM 아이콘을 개별적으로 확인하여 모두 안전하게 해제
    self:ReleaseGroupIcons(frame)

    -- [FIX] UnregisterMover로 Mover 프레임까지 완전 정리 (stale mover 방지)
    if DDingUI.Movers then
        local moverName = "DDingUI_Group_" .. groupName
        if DDingUI.Movers.UnregisterMover then
            DDingUI.Movers:UnregisterMover(moverName)
        elseif DDingUI.Movers.CreatedMovers and DDingUI.Movers.CreatedMovers[moverName] then
            DDingUI.Movers.CreatedMovers[moverName] = nil
        end
    end

    frame:Hide()
    self.groupFrames[groupName] = nil
end

-- ============================================================
-- [FIX] CDM 뷰어 Show/Hide → 그룹 프레임 표시 상태 동기화
-- ContainerSync에서 OnShow/OnHide 훅으로 호출됨
-- ============================================================

function GroupRenderer:SyncViewerVisibility(viewerName)
    -- 뷰어 → 그룹 이름 역매핑
    local targetGroup
    for groupName, mappedViewer in pairs(GROUP_VIEWER_MAP) do
        if mappedViewer == viewerName then
            targetGroup = groupName
            break
        end
    end
    if not targetGroup then return end

    local frame = self.groupFrames[targetGroup]
    if not frame then return end

    local viewer = _G[viewerName]
    if not viewer then return end

    if viewer:IsShown() then
        -- CDM이 뷰어를 보여줌 → 뷰어 숨김 플래그 해제 + 아이콘 표시
        local wasHidden = frame._viewerHidden
        frame._viewerHidden = false

        if frame._iconCount and frame._iconCount > 0 then
            frame:Show()
            for i = 1, (frame._iconCount or 0) do
                local ic = frame._managedIcons and frame._managedIcons[i]
                -- [FIX] _ddingHidden 아이콘은 Show하지 않음 (BuffTrackerBar 추적 중)
                if ic and not ic._ddingHidden then ic:Show() end
            end
        end

        -- [FIX] 전문화 변경 후 뷰어가 다시 나타나면 전체 재스캔 + 레이아웃 필요
        -- 이전 전문화의 아이콘이 managed에 남아있으므로 새 아이콘을 다시 가져와야 함
        if wasHidden then
            local fc = DDingUI.FrameController or DDingUI.CDMHookEngine
            if fc and fc.ForceReconcile then
                C_Timer.After(0.1, function()
                    if fc.initialized then
                        fc:ForceReconcile()
                    end
                end)
            end
        end
    else
        -- [FIX] CDM 뷰어 숨김 → 아이콘만 숨기고 프레임 크기는 유지
        -- _viewerHidden 플래그로 LayoutGroup 실행을 차단
        -- → 프레임 크기 보존 → 앵커된 그룹 위치 유지 (엘레베이터 방지)
        frame._viewerHidden = true
        for i = 1, (frame._iconCount or 0) do
            local ic = frame._managedIcons and frame._managedIcons[i]
            if ic then ic:Hide() end
        end
    end
end

