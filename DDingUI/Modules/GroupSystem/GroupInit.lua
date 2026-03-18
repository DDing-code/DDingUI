-- [GROUP SYSTEM] GroupInit: 초기화 + CDMHookEngine 연동
-- [REFACTOR] AuraEngine → CDMHookEngine 기반으로 전환
-- [REPARENT] ContainerSync 통합 — CDM 뷰어 은닉/복원
local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
if not DDingUI then return end

local GroupSystem = {}
DDingUI.GroupSystem = GroupSystem

-- Module references (파일 로드 후 세팅)
local CDMHookEngine
local GroupManager
local GroupRenderer
local ContainerSync  -- [REPARENT] CDM 뷰어 은닉/복원 모듈
local DynamicIconBridge  -- [DYNAMIC] CustomIcons 통합 어댑터

-- State
GroupSystem.initialized = false
GroupSystem.enabled = false

-- ============================================================
-- 프로필 접근
-- ============================================================

local L = LibStub("AceLocale-3.0"):GetLocale("DDingUI")

local function GetSettings()
    local profile = DDingUI.db and DDingUI.db.profile
    return profile and profile.groupSystem
end

-- [FIX] 그룹 표시명 (무버/편집모드에서 사용)
local GROUP_DISPLAY_NAMES = {
    ["Cooldowns"] = "핵심 능력",
    ["Buffs"]     = "강화 효과",
    ["Utility"]   = "보조 능력",
}

local function GetGroupDisplayName(groupName)
    if GROUP_DISPLAY_NAMES[groupName] then
        return GROUP_DISPLAY_NAMES[groupName]
    end
    -- 동적 그룹: 설정에 저장된 name 필드 사용
    local gs = GetSettings()
    if gs and gs.groups and gs.groups[groupName] and gs.groups[groupName].name then
        return gs.groups[groupName].name
    end
    return groupName
end

-- ============================================================
-- Mover 등록
-- ============================================================

local function RegisterGroupMovers()
    if not DDingUI.Movers or not DDingUI.Movers.RegisterMover then return end

    local gs = GetSettings()
    if not gs or not gs.groups then return end

    -- 핵심 3대 그룹: 프록시 앵커(DDingUI_Anchor_*)를 무버 대상으로 사용
    -- 프록시를 움직이면 그룹 위치 설정도 같이 갱신
    local PROXY_MOVER_MAP = {
        ["Cooldowns"] = { proxy = "DDingUI_Anchor_Cooldowns", display = "핵심 능력" },
        ["Buffs"]     = { proxy = "DDingUI_Anchor_Buffs",     display = "강화 효과" },
        ["Utility"]   = { proxy = "DDingUI_Anchor_Utility",   display = "보조 능력" },
    }

    for groupName, groupSettings in pairs(gs.groups) do
        if groupSettings.enabled then
            local proxyInfo = PROXY_MOVER_MAP[groupName]

            if proxyInfo then
                -- [FIX] 핵심 그룹: 프록시 앵커를 무버로 등록
                local proxyFrame = _G[proxyInfo.proxy]
                if proxyFrame then
                    local moverName = proxyInfo.proxy  -- 프록시 이름을 무버 키로 사용

                    -- MoverToModuleMapping: 위치를 groupSystem.groups.X에 저장
                    if DDingUI.Movers.RegisterModuleMapping then
                        DDingUI.Movers:RegisterModuleMapping(moverName, {
                            path = "groupSystem.groups." .. groupName,
                            xKey = "offsetX",
                            yKey = "offsetY",
                            attachKey = "attachTo",
                            pointKey = "anchorPoint",
                            selfPointKey = "selfPoint",
                        })
                    end

                    if not DDingUI.Movers.CreatedMovers[moverName] then
                        DDingUI.Movers:RegisterMover(proxyFrame, moverName, proxyInfo.display, nil, nil, true)
                    else
                        -- [FIX] 이미 등록된 Mover → 위치만 재로드 (새 스펙 데이터 반영)
                        -- RegisterMover는 CreatedMovers에 이미 있으면 early return (L909)
                        -- → LoadMoverPosition 미호출 → 새 스펙 오프셋이 프록시에 미적용
                        DDingUI.Movers:LoadMoverPosition(moverName)
                    end
                end

                -- 기존 DDingUI_Group_* 무버 제거 (목록에서 사라지도록)
                local oldMoverName = "DDingUI_Group_" .. groupName
                if DDingUI.Movers.CreatedMovers[oldMoverName] then
                    DDingUI.Movers:UnregisterMover(oldMoverName)
                end
            else
                -- 동적/커스텀 그룹: 기존 방식 유지 (그룹 프레임 직접 등록)
                local frame = GroupRenderer and GroupRenderer.groupFrames and GroupRenderer.groupFrames[groupName]
                if frame then
                    local moverName = "DDingUI_Group_" .. groupName

                    if DDingUI.Movers.RegisterModuleMapping then
                        DDingUI.Movers:RegisterModuleMapping(moverName, {
                            path = "groupSystem.groups." .. groupName,
                            xKey = "offsetX",
                            yKey = "offsetY",
                            attachKey = "attachTo",
                            pointKey = "anchorPoint",
                            selfPointKey = "selfPoint",
                        })
                    end

                    if not DDingUI.Movers.CreatedMovers[moverName] then
                        DDingUI.Movers:RegisterMover(frame, moverName, GetGroupDisplayName(groupName))
                    else
                        -- [FIX] 이미 등록된 동적 그룹 Mover → 위치만 재로드
                        DDingUI.Movers:LoadMoverPosition(moverName)
                    end
                end
            end
        end
    end
end

-- ============================================================
-- [DYNAMIC] CustomIcons 그룹 → GroupSystem 동적 그룹 동기화
-- dynamicIcons.groups의 사용자 정의 그룹을 GroupSystem.groups에 반영
-- (DoFullUpdate보다 앞에 정의해야 호출 가능)
-- ============================================================

local DYNAMIC_GROUP_DEFAULTS = {
    groupType = "dynamic",
    autoFilter = "ALL",
    enabled = true,
    iconSize = 36,
    aspectRatioCrop = 1.0,
    spacing = 2,
    zoom = 0.08,
    borderSize = 1,
    borderColor = { 0, 0, 0, 1 },
    direction = "RIGHT",
    growDirection = "DOWN",
    rowLimit = 12,
    swipeColor = { 0, 0, 0, 0.8 },
    swipeReverse = true,
    anchorPoint = "CENTER",
    attachTo = "UIParent", -- [FIX] 앵커 프레임 저장용
    offsetX = 0,
    offsetY = -120,
}

local function SyncDynamicGroups(gs)
    local bridge = DDingUI.DynamicIconBridge
    if not bridge then return end

    local dynamicGroups = bridge:GetDynamicGroups()

    -- 1. 다음 order 번호 계산 (기존 그룹 최대 order + 1)
    local maxOrder = 3
    for _, settings in pairs(gs.groups) do
        if settings.order and settings.order > maxOrder then
            maxOrder = settings.order
        end
    end

    -- 2. 새 dynamic 그룹 추가 (CustomIcons에 있는데 GroupSystem에 없는 것)
    for sourceKey, info in pairs(dynamicGroups) do
        -- 이미 매핑된 GroupSystem 그룹이 있는지 확인
        local foundSettings = nil
        for _, settings in pairs(gs.groups) do
            if settings.groupType == "dynamic" and settings.sourceGroupKey == sourceKey then
                foundSettings = settings
                break
            end
        end

        -- [FIX] 기존 그룹도 iconSize/aspectRatioCrop가 기본값이면 1번 아이콘에서 업데이트
        if foundSettings then
            -- [FIX] 그룹 표시명 동기화 (CustomIcons 이름 → GroupSystem 그룹)
            if info.name and (not foundSettings.name or foundSettings.name:match("^dyn_")) then
                foundSettings.name = info.name
            end

            local profile = DDingUI.db and DDingUI.db.profile
            local dynDB = profile and profile.dynamicIcons
            if dynDB and dynDB.iconData then
                local needSize = (foundSettings.iconSize == nil or foundSettings.iconSize == DYNAMIC_GROUP_DEFAULTS.iconSize)
                local needAR = (foundSettings.aspectRatioCrop == nil or foundSettings.aspectRatioCrop == 1.0)
                if needSize or needAR then
                    local dynGroup = dynDB.groups and dynDB.groups[sourceKey]
                    local firstIconKey = dynGroup and dynGroup.icons and dynGroup.icons[1]
                    local firstData = firstIconKey and dynDB.iconData[firstIconKey]
                    local firstSettings = firstData and firstData.settings
                    if firstSettings then
                        if needSize and firstSettings.iconSize then
                            foundSettings.iconSize = firstSettings.iconSize
                        end
                        if needAR and firstSettings.aspectRatio and firstSettings.aspectRatio ~= 1.0 then
                            foundSettings.aspectRatioCrop = firstSettings.aspectRatio
                        end
                    end
                end
            end
        end

        local gsGroupKey = "dyn_" .. sourceKey
        if not foundSettings then
            -- 사용자가 삭제한 그룹이면 재생성하지 않음
            if gs.deletedGroups and gs.deletedGroups[gsGroupKey] then
                foundSettings = true  -- 삭제된 그룹 마커
                -- [FIX] CustomIcons DB에 남아있는 고스트 데이터 원천 삭제
                local ci = DDingUI.CustomIcons
                if ci and ci.RemoveGroup then
                    ci:RemoveGroup(sourceKey)
                end
            end
        end

        if not foundSettings then
            maxOrder = maxOrder + 1
            -- GroupSystem 그룹 키: "dyn_" 접두사 + sourceKey
            local newGroup = {}
            for k, v in pairs(DYNAMIC_GROUP_DEFAULTS) do
                if type(v) == "table" then
                    newGroup[k] = { unpack(v) }
                else
                    newGroup[k] = v
                end
            end
            newGroup.order = maxOrder
            newGroup.sourceGroupKey = sourceKey  -- CustomIcons 그룹 매핑
            newGroup.enabled = info.enabled
            newGroup.name = info.name  -- [FIX] 그룹 표시명 마이그레이션

            -- [FIX] 기존 CustomIcons 그룹 위치 마이그레이션
            -- 1순위: dynamicIcons.groups[sourceKey].settings.position (직접 저장)
            local profile = DDingUI.db and DDingUI.db.profile
            local dynDB = profile and profile.dynamicIcons
            local dynSettings = dynDB and dynDB.groups and dynDB.groups[sourceKey]
                and dynDB.groups[sourceKey].settings
            if dynSettings then
                -- 위치 마이그레이션
                if dynSettings.position then
                    newGroup.offsetX = dynSettings.position.x or 0
                    newGroup.offsetY = dynSettings.position.y or 0
                    if dynSettings.anchorFrame and dynSettings.anchorFrame ~= "" then
                        newGroup.attachTo = dynSettings.anchorFrame
                    end
                    if dynSettings.anchorTo then
                        newGroup.anchorPoint = dynSettings.anchorTo
                    end
                    newGroup._moverSaved = true  -- CreateGroupFrame에서 뷰어 마이그레이션 건너뛰기
                end

                -- [FIX] 시각적 설정 마이그레이션 (CustomIcons 그룹 → GroupSystem 그룹)
                if dynSettings.iconSize then
                    newGroup.iconSize = dynSettings.iconSize
                end
                if dynSettings.spacing then
                    newGroup.spacing = dynSettings.spacing
                end
                if dynSettings.growthDirection then
                    newGroup.direction = dynSettings.growthDirection
                end
                if dynSettings.rowGrowthDirection then
                    newGroup.growDirection = dynSettings.rowGrowthDirection
                end
                if dynSettings.maxIconsPerRow then
                    newGroup.rowLimit = dynSettings.maxIconsPerRow
                end
                if dynSettings.anchorFrom then
                    newGroup.selfPoint = dynSettings.anchorFrom
                end
                -- [FIX] 종횡비/줌/테두리 마이그레이션 (CustomIcons → GroupSystem)
                -- CustomIcons는 aspectRatio, GroupSystem은 aspectRatioCrop
                if dynSettings.aspectRatio and dynSettings.aspectRatio ~= 1.0 then
                    newGroup.aspectRatioCrop = dynSettings.aspectRatio
                end
                if dynSettings.zoom then
                    newGroup.zoom = dynSettings.zoom
                end
                if dynSettings.borderSize then
                    newGroup.borderSize = dynSettings.borderSize
                end
                if dynSettings.borderColor then
                    newGroup.borderColor = { unpack(dynSettings.borderColor) }
                end
            else
                -- 2순위: movers 테이블에서 위치 데이터 추출 (무버 저장 형식: "point,relFrame,relPoint,x,y")
                local movers = profile and profile.movers
                local moverStr = movers and movers["DDingUI_DynGroup_" .. sourceKey]
                if moverStr and type(moverStr) == "string" then
                    local pt, relFrame, relPt, sx, sy = strsplit(",", moverStr)
                    local mx, my = tonumber(sx), tonumber(sy)
                    if mx and my then
                        newGroup.anchorPoint = relPt or "CENTER"
                        newGroup.offsetX = mx
                        newGroup.offsetY = my
                        if relFrame and relFrame ~= "" and relFrame ~= "UIParent" then
                            newGroup.attachTo = relFrame
                        end
                        newGroup._moverSaved = true
                    end
                end
            end

            -- [FIX] 그룹 설정에 아이콘 크기/종횡비가 기본값이면 → 1번 아이콘 기준으로 통일
            -- dynSettings에서 못 읽었거나, 그룹 수준에 저장되지 않은 경우
            if dynDB and dynDB.iconData then
                local needAR = (newGroup.aspectRatioCrop == nil or newGroup.aspectRatioCrop == 1.0)
                local needSize = (newGroup.iconSize == nil or newGroup.iconSize == DYNAMIC_GROUP_DEFAULTS.iconSize)
                local needZoom = (newGroup.zoom == nil or newGroup.zoom == DYNAMIC_GROUP_DEFAULTS.zoom)

                if needAR or needSize or needZoom then
                    -- 소속 아이콘 중 1번째 아이콘의 설정을 그룹 기준으로 사용
                    local dynGroup = dynDB.groups and dynDB.groups[sourceKey]
                    local firstIconKey = dynGroup and dynGroup.icons and dynGroup.icons[1]
                    local firstIconData = firstIconKey and dynDB.iconData[firstIconKey]
                    local firstSettings = firstIconData and firstIconData.settings

                    if firstSettings then
                        if needSize and firstSettings.iconSize then
                            newGroup.iconSize = firstSettings.iconSize
                        end
                        if needAR and firstSettings.aspectRatio and firstSettings.aspectRatio ~= 1.0 then
                            newGroup.aspectRatioCrop = firstSettings.aspectRatio
                        end
                        if needZoom and firstSettings.zoom then
                            newGroup.zoom = firstSettings.zoom
                        end
                    end
                end
            end

            -- [FIX] 모든 마이그레이션 완료 플래그 설정 (새 그룹이 MigrateToViewerGroups 재실행을 트리거하지 않도록)
            newGroup._selfPointMigV4 = true
            newGroup._viewerPosMigV3 = true
            newGroup._viewerSettingsMigV1 = true
            newGroup._viewerSettingsMigV2 = true

            gs.groups[gsGroupKey] = newGroup
        end
    end

    -- 3. 삭제된 dynamic 그룹 제거 (GroupSystem에 있는데 CustomIcons에 없는 것)
    local toRemove = {}
    for gsGroupKey, settings in pairs(gs.groups) do
        if settings.groupType == "dynamic" and settings.sourceGroupKey then
            if not dynamicGroups[settings.sourceGroupKey] then
                toRemove[#toRemove + 1] = gsGroupKey
            end
        end
    end
    for _, key in ipairs(toRemove) do
        gs.groups[key] = nil
    end

    -- [FIX] 4. sourceGroupKey 누락 동적 그룹 자동 복구
    -- groupType="dynamic"이지만 sourceGroupKey가 없으면 CustomIcons 그룹 생성 후 연결
    local ci = DDingUI.CustomIcons
    if ci and ci.CreateDynamicGroup then
        for gsGroupKey, settings in pairs(gs.groups) do
            if settings.groupType == "dynamic" and not settings.sourceGroupKey then
                local sourceKey = ci:CreateDynamicGroup(settings.name or gsGroupKey)
                if sourceKey then
                    settings.sourceGroupKey = sourceKey
                end
            end
        end
    end
end

-- ============================================================
-- 메인 업데이트
-- [REFACTOR] AuraEngine → CDMHookEngine 맵 기반
-- ============================================================

local function DoFullUpdate()
    if not GroupSystem.enabled then return end

    local gs = GetSettings()
    if not gs then return end

    -- [REPARENT] 맵 재구축 (뷰어 활성화 상태 변경 즉시 반영)
    if CDMHookEngine and CDMHookEngine.ScanCDMViewers then
        CDMHookEngine:ScanCDMViewers()
    end

    -- 1. CDMHookEngine 맵 → 그룹별 분류
    local classified = GroupManager:ClassifyAll()

    -- 2. 렌더링 (CDM 프레임 re-parent)
    -- [FIX] CDM + dynamic 병합: UpdateGroup이 두 타입 모두 처리
    local processedDynamicGroups = {}
    for groupName, iconList in pairs(classified) do
        local groupSettings = gs.groups and gs.groups[groupName]
        if groupSettings and groupSettings.enabled then
            GroupRenderer:UpdateGroup(groupName, iconList, groupSettings)
            -- dynamic 그룹이 CDM 경로에서 처리됨 → UpdateDynamicGroup에서 스킵
            if groupSettings.groupType == "dynamic" then
                processedDynamicGroups[groupName] = true
            end
        end
    end

    -- [DYNAMIC] 동적 그룹 동기화 + 업데이트
    -- [FIX] CDM 경로에서 이미 처리된 동적 그룹은 스킵 (이중 렌더링 방지)
    SyncDynamicGroups(gs)
    if gs.groups then
        for groupName, groupSettings in pairs(gs.groups) do
            if groupSettings.groupType == "dynamic" and groupSettings.enabled
               and not processedDynamicGroups[groupName] then
                GroupRenderer:UpdateDynamicGroup(groupName, groupSettings)
            end
        end
    end

    -- 비활성/미분류 그룹 숨기기 + 관리 아이콘 해제
    -- [FIX] 삭제된 그룹의 stale 프레임/mover도 완전 정리
    local staleGroups
    for groupName, frame in pairs(GroupRenderer.groupFrames) do
        local groupSettings = gs.groups and gs.groups[groupName]
        if not groupSettings then
            -- 설정이 없는 그룹 = 삭제됨 → DestroyGroup으로 완전 정리
            if not staleGroups then staleGroups = {} end
            staleGroups[#staleGroups + 1] = groupName
        -- [DYNAMIC] 동적 그룹은 classified에 없어도 정상 (별도 업데이트)
        elseif groupSettings.groupType == "dynamic" then
            -- 동적 그룹: 위에서 이미 처리됨, 스킵
        elseif not groupSettings.enabled then
            -- 비활성 그룹: 아이콘 해제 + 숨김
            GroupRenderer:ReleaseGroupIcons(frame)
            frame:Hide()
        elseif not classified[groupName] or #classified[groupName] == 0 then
            -- [FIX] 활성 그룹이지만 아이콘 0개: 아이콘만 해제, 프레임은 숨기지 않음
            -- 숨기면 이 그룹에 앵커된 시전바/자원바/다른 그룹의 앵커가 끊어져
            -- UIParent로 폴백 → 오프셋 누적(엘레베이터 현상) 발생
            GroupRenderer:ReleaseGroupIcons(frame)
        end
    end
    if staleGroups then
        for _, groupName in ipairs(staleGroups) do
            GroupRenderer:DestroyGroup(groupName)
        end
    end

    -- [REPARENT] CDM 뷰어 동기화 (관리 아이콘 수에 따라 은닉/복원)
    if ContainerSync then
        ContainerSync:SyncAll()
    end

end

-- DoFullUpdate를 외부에서 호출 가능하도록 노출 (DynamicIconBridge 등)
function GroupSystem:DoFullUpdate()
    DoFullUpdate()
end

-- [DYNAMIC] Config UI에서 호출: CustomIcons 그룹 동기화
function GroupSystem:SyncDynamicGroups()
    local gs = GetSettings()
    if gs then
        SyncDynamicGroups(gs)
    end
end

-- CDMHookEngine 콜백
local function OnHookEngineUpdate(updateType)
    DoFullUpdate()
end

-- [INTEGRATION] UNIT_AURA 이벤트 → 디바운스 DoFullUpdate
-- aura 타입 아이콘 상태 변경 시 GroupRenderer가 즉시 위치 배정
local auraUpdatePending = false
local auraEventFrame = CreateFrame("Frame")
auraEventFrame:RegisterEvent("UNIT_AURA")
auraEventFrame:SetScript("OnEvent", function(self, event, unit)
    if unit ~= "player" then return end
    if auraUpdatePending then return end
    auraUpdatePending = true
    C_Timer.After(0.15, function()
        auraUpdatePending = false
        if initialized then
            DoFullUpdate()
        end
    end)
end)

-- ============================================================
-- CDM 뷰어 Layout 트리거 (비활성화 시 원래 위치 복원)
-- ============================================================

local function TriggerCDMRelayout()
    local viewers = { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer" }
    for _, name in pairs(viewers) do
        local viewer = _G[name]
        if viewer and viewer.Layout then
            local ok = pcall(viewer.Layout, viewer)
        end
    end
end

-- ============================================================
-- [REPARENT] DB 마이그레이션: 뷰어별 3그룹 보장
-- 기존 프로필에 "All" 그룹만 있는 경우 → Cooldowns/Buffs/Utility 생성
-- ============================================================

local VIEWER_GROUP_DEFAULTS = {
    {
        name = "Cooldowns",
        autoFilter = "COOLDOWN",
        order = 1,
        offsetY = -200,
    },
    {
        name = "Buffs",
        autoFilter = "HELPFUL",
        order = 2,
        offsetY = -250,
    },
    {
        name = "Utility",
        autoFilter = "UTILITY",
        order = 3,
        offsetY = -300,
    },
}

local GROUP_VIEWER_MAP = {
    ["Cooldowns"] = "EssentialCooldownViewer",
    ["Buffs"]     = "BuffIconCooldownViewer",
    ["Utility"]   = "UtilityCooldownViewer",
}

local CURRENT_GROUP_SYSTEM_VERSION = 1  -- 1.2.4

local function MigrateToViewerGroups(gs)
    if not gs then return end

    local profileRef = DDingUI.db and DDingUI.db.profile
    -- 이미 현재 버전이면 마이그레이션 스킵
    if gs._groupSystemVersion and gs._groupSystemVersion >= CURRENT_GROUP_SYSTEM_VERSION then
        -- autoClassify만 보장
        if not gs.autoClassify then gs.autoClassify = true end
        return
    end

    -- autoClassify 활성화 (뷰어별 분류 필수)
    if not gs.autoClassify then
        gs.autoClassify = true
    end

    if not gs.groups then gs.groups = {} end

    -- 뷰어별 그룹 존재 여부 확인
    local allExist = true
    for _, def in ipairs(VIEWER_GROUP_DEFAULTS) do
        if not gs.groups[def.name] then
            allExist = false
            break
        end
    end

    -- Mover 위치 초기화 → CaptureViewerPositions가 뷰어 라이브 위치에서 재캡처
    for _, def in ipairs(VIEWER_GROUP_DEFAULTS) do
        if DDingUI.Movers and DDingUI.Movers.CreatedMovers then
            local moverName = "DDingUI_Group_" .. def.name
            DDingUI.Movers.CreatedMovers[moverName] = nil
        end
    end

    -- 뷰어 시각적 설정 → GroupSystem 그룹으로 복사
    -- 그룹 값이 기본값일 때만 덮어쓰기 (사용자 커스터마이징 보호)
    do
        local viewerProfiles = profileRef and profileRef.viewers

        for _, def in ipairs(VIEWER_GROUP_DEFAULTS) do
            local grp = gs.groups[def.name]
            if grp then
                local viewerName = GROUP_VIEWER_MAP[def.name]
                local vs = viewerName and viewerProfiles and viewerProfiles[viewerName]
                if vs then
                    -- 아이콘 크기 (그룹 기본값 36 → 뷰어 설정으로)
                    if grp.iconSize == 36 and vs.iconSize then
                        grp.iconSize = vs.iconSize
                    end
                    -- 아이콘 간격 (그룹 기본값 2 → 뷰어 설정으로)
                    if grp.spacing == 2 and vs.spacing then
                        grp.spacing = vs.spacing
                    end
                    -- [12.0.1] 종횡비 (그룹 기본값 1.0 → 뷰어 설정으로)
                    if grp.aspectRatioCrop == 1.0 and vs.aspectRatioCrop and vs.aspectRatioCrop ~= 1.0 then
                        grp.aspectRatioCrop = vs.aspectRatioCrop
                    end
                    -- [12.0.1] 줌 (그룹 기본값 0.08 → 뷰어 설정으로)
                    if grp.zoom == 0.08 and vs.zoom and vs.zoom ~= 0.08 then
                        grp.zoom = vs.zoom
                    end
                    -- [12.0.1] 테두리 크기/색상 (그룹 기본값 → 뷰어 설정으로)
                    if grp.borderSize == 1 and vs.borderSize ~= nil then
                        grp.borderSize = vs.borderSize
                    end
                    if vs.borderColor then
                        grp.borderColor = { unpack(vs.borderColor) }
                    end
                    -- 스택/차지 텍스트 (그룹 기본값 nil → 뷰어 설정으로)
                    if not grp.countTextSize and vs.countTextSize then
                        grp.countTextSize = vs.countTextSize
                    end
                    if not grp.countTextColor and vs.countTextColor then
                        grp.countTextColor = { unpack(vs.countTextColor) }
                    end
                    -- 쿨다운 텍스트 (그룹 기본값 nil → 뷰어 설정으로)
                    if not grp.cooldownFontSize and vs.cooldownFontSize then
                        grp.cooldownFontSize = vs.cooldownFontSize
                    end
                    if not grp.cooldownTextColor and vs.cooldownTextColor then
                        grp.cooldownTextColor = { unpack(vs.cooldownTextColor) }
                    end
                    -- 행 제한 (그룹 기본값 12 → 뷰어 설정으로)
                    if grp.rowLimit == 12 and vs.rowLimit ~= nil then
                        grp.rowLimit = vs.rowLimit
                    end
                    -- [12.0.1] 위치 관련 설정(attachTo, anchorPoint, selfPoint, offsetX/Y)은
                    -- V1에서 복사하지 않음 → CaptureViewerPositions가 라이브 뷰어 위치를 캡처하여 전담
                    -- (뷰어 프로필의 anchorOffset은 대부분 nil/0이고, anchorFrame은 구형 뷰어 이름이라 부정확)
                    -- 애니메이션 설정 (뷰어 → 그룹)
                    if vs.swipeColor and grp.swipeColor then
                        grp.swipeColor = { unpack(vs.swipeColor) }
                    end
                    if vs.swipeReverse ~= nil then
                        grp.swipeReverse = vs.swipeReverse
                    end
                    if vs.disableSwipeAnimation ~= nil and not grp.disableSwipeAnimation then
                        grp.disableSwipeAnimation = vs.disableSwipeAnimation
                    end
                    if vs.disableEdgeGlow ~= nil and not grp.disableEdgeGlow then
                        grp.disableEdgeGlow = vs.disableEdgeGlow
                    end
                    if vs.disableBlingAnimation ~= nil and not grp.disableBlingAnimation then
                        grp.disableBlingAnimation = vs.disableBlingAnimation
                    end
                    -- 차지 텍스트 앵커 (뷰어 → 그룹)
                    if not grp.chargeTextAnchor and vs.chargeTextAnchor then
                        grp.chargeTextAnchor = vs.chargeTextAnchor
                    end
                end
            end
        end
    end

    -- [12.0.1] V2 마이그레이션: V1 완료 프로필에서 누락된 종횡비/줌/앵커/테두리 보정
    for _, def in ipairs(VIEWER_GROUP_DEFAULTS) do
        local grp = gs.groups[def.name]
        if grp and grp._viewerSettingsMigV1 and not grp._viewerSettingsMigV2 then
            grp._viewerSettingsMigV2 = true
            local viewerName = GROUP_VIEWER_MAP[def.name]
            local profile = DDingUI.db and DDingUI.db.profile
            local vs = viewerName and profile and profile.viewers and profile.viewers[viewerName]
            if vs then
                if grp.aspectRatioCrop == 1.0 and vs.aspectRatioCrop and vs.aspectRatioCrop ~= 1.0 then
                    grp.aspectRatioCrop = vs.aspectRatioCrop
                end
                if grp.zoom == 0.08 and vs.zoom and vs.zoom ~= 0.08 then
                    grp.zoom = vs.zoom
                end
                if grp.borderSize == 1 and vs.borderSize ~= nil then
                    grp.borderSize = vs.borderSize
                end
                if vs.borderColor then
                    grp.borderColor = { unpack(vs.borderColor) }
                end
                if grp.attachTo == "UIParent" and vs.anchorFrame and vs.anchorFrame ~= "" then
                    grp.attachTo = vs.anchorFrame
                end
                if grp.anchorPoint == "CENTER" and vs.anchorPoint and vs.anchorPoint ~= "CENTER" then
                    grp.anchorPoint = vs.anchorPoint
                end
                -- [FIX] selfPoint 마이그레이션 (V2)
                if not grp.selfPoint or grp.selfPoint == "CENTER" then
                    if vs.selfPoint and vs.selfPoint ~= "CENTER" then
                        grp.selfPoint = vs.selfPoint
                    elseif vs.anchorPoint and vs.anchorPoint ~= "CENTER" then
                        grp.selfPoint = vs.anchorPoint
                    end
                end
                if grp.offsetX == 0 and vs.anchorOffsetX and vs.anchorOffsetX ~= 0 then
                    grp.offsetX = vs.anchorOffsetX
                end
                if grp.offsetY == 0 and vs.anchorOffsetY and vs.anchorOffsetY ~= 0 then
                    grp.offsetY = vs.anchorOffsetY
                end
            end
        end
    end

    -- [12.0.1] V3 마이그레이션: 방향, 텍스트 오프셋, 오라 글로우, 그룹 오프셋 등 전체 보완
    -- v1.2.3은 Blizzard 편집모드가 CDM 뷰어 위치를 관리 → DDingUI는 스킨만 담당
    -- 현재 버전은 뷰어를 숨기고 독립 그룹으로 대체 → 모든 파라미터 완전 이전 필요
    for _, def in ipairs(VIEWER_GROUP_DEFAULTS) do
        local grp = gs.groups[def.name]
        if grp and not grp._viewerSettingsMigV3 then
            grp._viewerSettingsMigV3 = true
            local viewerName = GROUP_VIEWER_MAP[def.name]
            local profile = DDingUI.db and DDingUI.db.profile
            local vs = viewerName and profile and profile.viewers and profile.viewers[viewerName]
            if vs then
                -- 1) primaryDirection → direction (성장 방향)
                -- CDM 뷰어: "CENTERED_HORIZONTAL", "Right", "Left and Up" 등
                -- GroupSystem: "RIGHT", "LEFT", "UP", "DOWN"
                if grp.direction == "RIGHT" and vs.primaryDirection then
                    local pd = vs.primaryDirection
                    if pd == "CENTERED_HORIZONTAL" or pd == "Centered Horizontal" then
                        grp.direction = "RIGHT" -- 센터 정렬은 레이아웃 엔진이 처리
                    elseif pd:match("^Left") or pd == "LEFT" then
                        grp.direction = "LEFT"
                    elseif pd:match("^Right") or pd == "RIGHT" then
                        grp.direction = "RIGHT"
                    elseif pd:match("^Up") or pd == "UP" then
                        grp.direction = "UP"
                    elseif pd:match("^Down") or pd == "DOWN" then
                        grp.direction = "DOWN"
                    end
                end
                -- 2) secondaryDirection → growDirection (줄바꿈 방향)
                if grp.growDirection == "DOWN" and vs.secondaryDirection then
                    local sd = vs.secondaryDirection
                    if sd == "Up" or sd == "UP" then
                        grp.growDirection = "UP"
                    elseif sd == "Down" or sd == "DOWN" then
                        grp.growDirection = "DOWN"
                    elseif sd == "Left" or sd == "LEFT" then
                        grp.growDirection = "LEFT"
                    elseif sd == "Right" or sd == "RIGHT" then
                        grp.growDirection = "RIGHT"
                    end
                end

                -- 3) 충전/스택 텍스트 오프셋
                if vs.countTextOffsetX and vs.countTextOffsetX ~= 0 and not grp.countTextOffsetX then
                    grp.countTextOffsetX = vs.countTextOffsetX
                end
                if vs.countTextOffsetY and vs.countTextOffsetY ~= 0 and not grp.countTextOffsetY then
                    grp.countTextOffsetY = vs.countTextOffsetY
                end

                -- 4) 쿨다운 텍스트 앵커/오프셋
                if vs.cooldownTextAnchor and vs.cooldownTextAnchor ~= "CENTER" and not grp.cooldownTextAnchor then
                    grp.cooldownTextAnchor = vs.cooldownTextAnchor
                end
                if vs.cooldownTextOffsetX and vs.cooldownTextOffsetX ~= 0 and not grp.cooldownTextOffsetX then
                    grp.cooldownTextOffsetX = vs.cooldownTextOffsetX
                end
                if vs.cooldownTextOffsetY and vs.cooldownTextOffsetY ~= 0 and not grp.cooldownTextOffsetY then
                    grp.cooldownTextOffsetY = vs.cooldownTextOffsetY
                end

                -- 5) 쿨다운 텍스트 그림자
                if vs.cooldownShadowOffsetX and vs.cooldownShadowOffsetX ~= 0 and not grp.cooldownShadowOffsetX then
                    grp.cooldownShadowOffsetX = vs.cooldownShadowOffsetX
                end
                if vs.cooldownShadowOffsetY and vs.cooldownShadowOffsetY ~= 0 and not grp.cooldownShadowOffsetY then
                    grp.cooldownShadowOffsetY = vs.cooldownShadowOffsetY
                end

                -- 6) 오라 스와이프 색상
                if vs.auraSwipeColor and not grp.auraSwipeColor then
                    grp.auraSwipeColor = { unpack(vs.auraSwipeColor) }
                end

                -- 7) 오라 글로우 전체 설정
                if vs.auraGlow ~= nil and grp.auraGlow == nil then
                    grp.auraGlow = vs.auraGlow
                end
                if vs.auraGlowType and not grp.auraGlowType then
                    grp.auraGlowType = vs.auraGlowType
                end
                if vs.auraGlowColor and not grp.auraGlowColor then
                    grp.auraGlowColor = { unpack(vs.auraGlowColor) }
                end
                if vs.auraGlowAutocastParticles and not grp.auraGlowAutocastParticles then
                    grp.auraGlowAutocastParticles = vs.auraGlowAutocastParticles
                end
                if vs.auraGlowAutocastFrequency and not grp.auraGlowAutocastFrequency then
                    grp.auraGlowAutocastFrequency = vs.auraGlowAutocastFrequency
                end
                if vs.auraGlowAutocastScale and not grp.auraGlowAutocastScale then
                    grp.auraGlowAutocastScale = vs.auraGlowAutocastScale
                end
                if vs.auraGlowButtonFrequency and not grp.auraGlowButtonFrequency then
                    grp.auraGlowButtonFrequency = vs.auraGlowButtonFrequency
                end

                -- 8) 그룹 상태 오프셋 (파티/레이드)
                if vs.groupOffsets and not grp.groupOffsets then
                    grp.groupOffsets = {}
                    if vs.groupOffsets.party then
                        grp.groupOffsets.party = { x = vs.groupOffsets.party.x, y = vs.groupOffsets.party.y }
                    end
                    if vs.groupOffsets.raid then
                        grp.groupOffsets.raid = { x = vs.groupOffsets.raid.x, y = vs.groupOffsets.raid.y }
                    end
                end

                -- 9) Buff 뷰어 전용: 지속시간 텍스트 전체
                if viewerName == "BuffIconCooldownViewer" then
                    if vs.durationTextAnchor and vs.durationTextAnchor ~= "TOP" and not grp.durationTextAnchor then
                        grp.durationTextAnchor = vs.durationTextAnchor
                    end
                    if vs.durationTextOffsetX and vs.durationTextOffsetX ~= 0 and not grp.durationTextOffsetX then
                        grp.durationTextOffsetX = vs.durationTextOffsetX
                    end
                    if vs.durationTextOffsetY and vs.durationTextOffsetY ~= 0 and not grp.durationTextOffsetY then
                        grp.durationTextOffsetY = vs.durationTextOffsetY
                    end
                    if vs.durationTextFont and not grp.durationTextFont then
                        grp.durationTextFont = vs.durationTextFont
                    end
                    if vs.durationTextSize and vs.durationTextSize ~= 14 and not grp.durationTextSize then
                        grp.durationTextSize = vs.durationTextSize
                    end
                    if vs.durationTextColor and not grp.durationTextColor then
                        grp.durationTextColor = { unpack(vs.durationTextColor) }
                    end
                end
            end
        end
    end

    -- [FIX] 핵심 3대 그룹 위치 보정: attachTo가 UIParent가 아니면 리셋 → CaptureViewerPositions가 재캡처
    -- 핵심 그룹은 항상 UIParent CENTER 기준이어야 함 (프록시 앵커는 그룹 프레임의 부모, attachTo와 무관)
    local CORE_GROUPS = { Cooldowns = true, Buffs = true, Utility = true }
    if gs and gs.groups then
        for groupName, grp in pairs(gs.groups) do
            if CORE_GROUPS[groupName] and grp.attachTo and grp.attachTo ~= "UIParent" then
                grp.attachTo = "UIParent"
                grp.anchorPoint = "CENTER"
                grp.selfPoint = "CENTER"
                grp.offsetX = 0
                grp.offsetY = 0
                grp._moverSaved = nil  -- CaptureViewerPositions 재실행 허용
            end
        end
        -- 1회성: 이전 마이그레이션에서 잘못 캡처된 오프셋 → 재캡처 허용
        local profileRef2 = DDingUI.db and DDingUI.db.profile
        if profileRef2 and not profileRef2._coreGroupPosReset then
            profileRef2._coreGroupPosReset = true
            for groupName, _ in pairs(CORE_GROUPS) do
                local grp = gs.groups[groupName]
                if grp then
                    grp._moverSaved = nil
                    grp.offsetX = 0
                    grp.offsetY = 0
                    grp.attachTo = "UIParent"
                    grp.anchorPoint = "CENTER"
                    grp.selfPoint = "CENTER"
                end
            end
        end
    end

    -- 핵심 그룹 위치 초기화 → CaptureViewerPositions가 라이브 뷰어에서 재캡처
    local CORE_GROUPS_POS = { Cooldowns = true, Buffs = true, Utility = true }
    if gs.groups then
        for groupName, grp in pairs(gs.groups) do
            if CORE_GROUPS_POS[groupName] then
                grp._moverSaved = nil
                grp.offsetX = 0
                grp.offsetY = 0
                grp.attachTo = "UIParent"
                grp.anchorPoint = "CENTER"
                grp.selfPoint = "CENTER"
            end
        end
    end

    -- 누락된 뷰어 그룹 생성
    for _, def in ipairs(VIEWER_GROUP_DEFAULTS) do
        if not gs.groups[def.name] then
            gs.groups[def.name] = {
                order = def.order,
                autoFilter = def.autoFilter,
                enabled = true,
                iconSize = 36,
                aspectRatioCrop = 1.0,
                spacing = 2,
                zoom = 0.08,
                borderSize = 1,
                borderColor = { 0, 0, 0, 1 },
                direction = "RIGHT",
                growDirection = "DOWN",
                rowLimit = 12,
                anchorPoint = "CENTER",
                offsetX = 0,
                offsetY = def.offsetY or 0,  -- [FIX] v1.2.3 마이그레이션: 뷰어 위치 못 읽으면 폴백 오프셋 사용
                _viewerPosMigrated = true,
            }
        end
    end

    -- "All" 그룹 비활성화 (autoFilter="ALL"이면 모든 아이콘 흡수하므로)
    if gs.groups["All"] and gs.groups["All"].autoFilter == "ALL" then
        gs.groups["All"].enabled = false
    end

    -- [DYNAMIC] 기존 CDM 그룹에 groupType 마이그레이션
    for _, def in ipairs(VIEWER_GROUP_DEFAULTS) do
        local grp = gs.groups[def.name]
        if grp and not grp.groupType then
            grp.groupType = "cdm"
        end
    end

    -- attachTo 뷰어→그룹 프레임 마이그레이션
    -- 전 버전은 CDM 뷰어에 스킨만 씨워서 편집모드 위치에 종속 → 모듈들이 뷰어에 앵커
    -- 독립 그룹으로 변경되어 뷰어 이름 → 그룹 프레임 이름 → 프록시 앵커 이름으로 순차 변환
    if profileRef then
        local VIEWER_TO_GROUP = {
            ["EssentialCooldownViewer"] = "DDingUI_Group_Cooldowns",
            ["BuffIconCooldownViewer"]  = "DDingUI_Group_Buffs",
            ["UtilityCooldownViewer"]   = "DDingUI_Group_Utility",
        }

        -- 주자원바, 보조자원바, 시전바, 대상시전바, 버프바
        local simpleModules = { "powerBar", "secondaryPowerBar", "playerCastBar", "castBar", "focusCastBar", "targetCastBar", "buffBarViewer" }
        for _, modKey in ipairs(simpleModules) do
            local cfg = profileRef[modKey]
            if cfg and cfg.attachTo then
                local newTarget = VIEWER_TO_GROUP[cfg.attachTo]
                if newTarget then
                    cfg.attachTo = newTarget
                end
            end
        end

        -- 버프추적기: 전체 설정 + 개별 버프 설정
        local btCfg = profileRef.buffTrackerBar
        if btCfg then
            if btCfg.attachTo and VIEWER_TO_GROUP[btCfg.attachTo] then
                btCfg.attachTo = VIEWER_TO_GROUP[btCfg.attachTo]
            end
            -- 개별 버프 설정
            if btCfg.buffs then
                for _, buffCfg in pairs(btCfg.buffs) do
                    if buffCfg.attachTo and VIEWER_TO_GROUP[buffCfg.attachTo] then
                        buffCfg.attachTo = VIEWER_TO_GROUP[buffCfg.attachTo]
                    end
                    if buffCfg.iconAttachTo and VIEWER_TO_GROUP[buffCfg.iconAttachTo] then
                        buffCfg.iconAttachTo = VIEWER_TO_GROUP[buffCfg.iconAttachTo]
                    end
                    if buffCfg.textAnchorTo and VIEWER_TO_GROUP[buffCfg.textAnchorTo] then
                        buffCfg.textAnchorTo = VIEWER_TO_GROUP[buffCfg.textAnchorTo]
                    end
                end
            end
        end

        -- [V3] GroupSystem 그룹 자체의 attachTo (그룹 A → 뷰어 B 앵커링)
        if gs and gs.groups then
            for _, grp in pairs(gs.groups) do
                if grp.attachTo and VIEWER_TO_GROUP[grp.attachTo] then
                    grp.attachTo = VIEWER_TO_GROUP[grp.attachTo]
                end
            end
        end

        -- [V3] 뷰어 프로필의 anchorFrame (뷰어 간 앵커링)
        local viewerProfiles = profileRef.viewers
        if viewerProfiles then
            for _, vs in pairs(viewerProfiles) do
                if type(vs) == "table" and vs.anchorFrame and VIEWER_TO_GROUP[vs.anchorFrame] then
                    vs.anchorFrame = VIEWER_TO_GROUP[vs.anchorFrame]
                end
            end
        end

        -- [V3] 동적 아이콘 그룹의 anchorFrame
        local dynDB = profileRef.dynamicIcons
        if dynDB and dynDB.groups then
            for _, dynGroup in pairs(dynDB.groups) do
                if dynGroup.settings and dynGroup.settings.anchorFrame
                    and VIEWER_TO_GROUP[dynGroup.settings.anchorFrame] then
                    dynGroup.settings.anchorFrame = VIEWER_TO_GROUP[dynGroup.settings.anchorFrame]
                end
            end
        end

        -- [V3] movers 테이블의 relFrame (저장 형식: "point,relFrame,relPoint,x,y")
        local movers = profileRef.movers
        if movers then
            for moverName, moverStr in pairs(movers) do
                if type(moverStr) == "string" then
                    for viewerName, groupFrame in pairs(VIEWER_TO_GROUP) do
                        if moverStr:find(viewerName, 1, true) then
                            movers[moverName] = moverStr:gsub(viewerName, groupFrame)
                            break
                        end
                    end
                end
            end
        end

    end

    -- DDingUI_Group_* → DDingUI_Anchor_* 프록시 앵커 마이그레이션
    -- 프록시 앵커는 영구 프레임으로, CDM 뷰어 재생성 시에도 앵커가 끊어지지 않음
    if profileRef then
        local GROUP_TO_PROXY = {
            ["DDingUI_Group_Cooldowns"] = "DDingUI_Anchor_Cooldowns",
            ["DDingUI_Group_Utility"]   = "DDingUI_Anchor_Utility",
            ["DDingUI_Group_Buffs"]     = "DDingUI_Anchor_Buffs",
            ["EssentialCooldownViewer"] = "DDingUI_Anchor_Cooldowns",
            ["UtilityCooldownViewer"]   = "DDingUI_Anchor_Utility",
            ["BuffIconCooldownViewer"]  = "DDingUI_Anchor_Buffs",
        }

        local simpleModules = { "powerBar", "secondaryPowerBar", "playerCastBar", "castBar", "focusCastBar", "targetCastBar", "buffBarViewer" }
        for _, modKey in ipairs(simpleModules) do
            local cfg = profileRef[modKey]
            if cfg and cfg.attachTo and GROUP_TO_PROXY[cfg.attachTo] then
                cfg.attachTo = GROUP_TO_PROXY[cfg.attachTo]
            end
        end

        -- 버프추적기
        local btCfg = profileRef.buffTrackerBar
        if btCfg then
            if btCfg.attachTo and GROUP_TO_PROXY[btCfg.attachTo] then
                btCfg.attachTo = GROUP_TO_PROXY[btCfg.attachTo]
            end
        end

    end

    -- 그룹 selfPoint 보정: nil이면 anchorPoint와 동일하게
    if gs and gs.groups then
        for _, grp in pairs(gs.groups) do
            if not grp.selfPoint and grp.anchorPoint then
                grp.selfPoint = grp.anchorPoint
            end
        end
    end

    -- 모듈(자원바/시전바/버프바) selfPoint 보정
    if profileRef then
        local ANCHOR_FLIP = {
            TOP = "BOTTOM", BOTTOM = "TOP",
            LEFT = "RIGHT", RIGHT = "LEFT",
            TOPLEFT = "BOTTOMLEFT", TOPRIGHT = "BOTTOMRIGHT",
            BOTTOMLEFT = "TOPLEFT", BOTTOMRIGHT = "TOPRIGHT",
        }

        local moduleKeys = { "powerBar", "secondaryPowerBar", "castBar", "playerCastBar", "focusCastBar", "targetCastBar", "buffTrackerBar", "buffBarViewer" }
        for _, modKey in ipairs(moduleKeys) do
            local cfg = profileRef[modKey]
            if cfg and not cfg.selfPoint then
                local attachTo = cfg.attachTo or "UIParent"
                local anchorPt = cfg.anchorPoint or "CENTER"
                if attachTo ~= "UIParent" and attachTo ~= "" then
                    cfg.selfPoint = ANCHOR_FLIP[anchorPt] or anchorPt
                else
                    cfg.selfPoint = anchorPt
                end
            end
        end
    end

    -- 마이그레이션 완료: 버전 설정
    gs._groupSystemVersion = CURRENT_GROUP_SYSTEM_VERSION

end

-- (SyncDynamicGroups는 파일 상단 DoFullUpdate 앞에 정의됨)

-- ============================================================
-- 활성화/비활성화
-- [REFACTOR] AuraEngine → CDMHookEngine
-- ============================================================

-- ============================================================
-- [FIX] 고아(orphan) 동적 아이콘 클린업
-- 이전 코드의 불완전한 삭제 로직으로 DB에서는 그룹이 삭제되었지만
-- 화면에 _ddIsManaged 프레임이 남아있는 경우를 처리
-- ============================================================

local function CleanupOrphanedDynamicIcons()
    local bridge = DDingUI.DynamicIconBridge
    if not bridge then return end

    -- 1. 현재 활성 그룹들이 관리하는 모든 아이콘 키 수집
    local managedByGroups = {}
    if GroupRenderer and GroupRenderer.groupFrames then
        for _, frame in pairs(GroupRenderer.groupFrames) do
            if frame._managedIcons then
                for _, icon in pairs(frame._managedIcons) do
                    if icon and icon._ddIconKey then
                        managedByGroups[icon._ddIconKey] = true
                    end
                end
            end
        end
    end

    -- 2. 활성 GroupSystem 그룹의 sourceGroupKey 리스트 수집
    local activeSourceKeys = {}
    local gs = GetSettings()
    if gs and gs.groups then
        for _, grpSettings in pairs(gs.groups) do
            if grpSettings.enabled and grpSettings.sourceGroupKey then
                activeSourceKeys[grpSettings.sourceGroupKey] = true
            end
        end
    end

    -- 3. CustomIcons 전체 프레임에서 고아 프레임 찾기
    local ci = DDingUI.CustomIcons
    if ci and ci.GetAllIconFrames then
        local allFrames = ci:GetAllIconFrames()
        for iconKey, frame in pairs(allFrames) do
            if frame._ddIsManaged and not managedByGroups[iconKey] then
                -- 이 프레임은 관리 태그가 남아있지만 어떤 그룹에도 속하지 않음 → 고아
                bridge:ReleaseFrame(frame, iconKey)
                frame:Hide()
            end
        end
    end

    -- 4. CustomIcons 네이티브 컨테이너(DDingUI_DynGroup_*, DDingUI_DynTrinket_*) 클린업
    -- GroupSystem이 활성이면 CustomIcons의 레이아웃을 억제하는데,
    -- 이미 삭제된 그룹의 컨테이너는 억제되지 않고 그대로 화면에 남아있음
    if ci and ci.GetGroupFrames then
        local groupFrames = ci:GetGroupFrames()
        if groupFrames then
            for groupKey, container in pairs(groupFrames) do
                -- GroupSystem에서 활성 그룹으로 매핑되지 않은 컨테이너 → 숨기기
                if not activeSourceKeys[groupKey] then
                    -- 컨테이너 안의 아이콘들도 숨기기
                    local children = { container:GetChildren() }
                    for _, child in ipairs(children) do
                        child:Hide()
                    end
                    container:Hide()
                end
            end
        end
    end

    -- 5. UIParent 자식들 중 _ddIsManaged가 남아있는 프레임도 정리
    local children = { UIParent:GetChildren() }
    for _, child in ipairs(children) do
        if child._ddIsManaged and child._ddIconKey and not managedByGroups[child._ddIconKey] then
            bridge:ReleaseFrame(child, child._ddIconKey)
            child:Hide()
        end
        -- DDingUI_DynGroup_ / DDingUI_DynTrinket_ / DDingUI_DynSlot_ 이름의 고아 컨테이너
        local ok, name = pcall(child.GetName, child)
        if ok and name then
            local dynGroupKey = name:match("^DDingUI_DynGroup_(.+)$")
            if dynGroupKey and not activeSourceKeys[dynGroupKey] then
                local subs = { pcall(child.GetChildren, child) }
                if subs[1] then  -- pcall success
                    for i = 2, #subs do
                        local sub = subs[i]
                        if sub and sub.Hide then pcall(sub.Hide, sub) end
                    end
                end
                pcall(child.Hide, child)
            end
        end
    end
end

-- ============================================================
-- 활성화
-- ============================================================

function GroupSystem:Enable()
    if self.enabled then return end

    local gs = GetSettings()
    if not gs then return end

    -- [REPARENT] DB 마이그레이션: 뷰어별 3그룹 보장
    MigrateToViewerGroups(gs)

    -- 모듈 참조
    CDMHookEngine = DDingUI.CDMHookEngine
    GroupManager = DDingUI.GroupManager
    GroupRenderer = DDingUI.GroupRenderer
    ContainerSync = DDingUI.ContainerSync  -- [REPARENT]
    DynamicIconBridge = DDingUI.DynamicIconBridge  -- [DYNAMIC]

    if not CDMHookEngine or not GroupManager or not GroupRenderer then
        return
    end

    -- ★ CastBar 강제 생성 (lazy-created → 다른 시스템보다 먼저 존재해야 함)
    -- RegisterGroupMovers/LoadMoverPosition/Refresh가 CastBar를 앵커로 사용
    if not _G["DDingUICastBar"] and not DDingUI.castBar then
        if DDingUI.GetCastBar then
            pcall(function() DDingUI:GetCastBar() end)
        end
    end

    -- CDMHookEngine 초기화 (뷰어 존재 확인 포함)
    local ok = CDMHookEngine:Initialize()
    if not ok then
        -- 뷰어 미로드 → 2초 후 재시도
        C_Timer.After(2, function()
            if not GroupSystem.enabled then
                GroupSystem:Enable()
            end
        end)
        return
    end

    self.enabled = true
    -- [FIX/v1.2.3] 블리자드 편집모드 뷰어 위치 → 그룹 위치 동기화
    -- _moverSaved가 없는 그룹만 캡처 (수동 위치 조정된 그룹은 건드리지 않음)
    local _viewerCaptured = {}
    local function CaptureViewerPositions()
        local VIEWER_TO_GROUP = {
            ["EssentialCooldownViewer"] = "Cooldowns",
            ["BuffIconCooldownViewer"]  = "Buffs",
            ["UtilityCooldownViewer"]   = "Utility",
        }
        local uiCX, uiCY = UIParent:GetCenter()
        if not uiCX or not gs.groups then return end

        for viewerName, groupName in pairs(VIEWER_TO_GROUP) do
            if not _viewerCaptured[groupName] then
                local grp = gs.groups[groupName]
                -- _moverSaved가 없는 그룹만 캡처 (처음 마이그레이션 또는 리셋된 프로필)
                if grp and not grp._moverSaved then
                    local viewer = _G[viewerName]
                    if viewer and viewer:IsShown() then
                        local cx, cy = viewer:GetCenter()
                        if cx and cy then
                            local ox = cx - uiCX
                            local oy = cy - uiCY
                            -- 뷰어가 유효한 위치에 있을 때만 저장
                            if math.abs(ox) > 1 or math.abs(oy) > 1 then
                                grp.offsetX = ox
                                grp.offsetY = oy
                                grp.anchorPoint = "CENTER"
                                grp.selfPoint = "CENTER"
                                grp.attachTo = "UIParent"
                                grp._moverSaved = true
                                _viewerCaptured[groupName] = true
                                -- 프록시 앵커 즉시 업데이트
                                local proxy = _G["DDingUI_Anchor_" .. groupName]
                                if proxy then
                                    proxy:ClearAllPoints()
                                    proxy:SetPoint("CENTER", UIParent, "CENTER", ox, oy)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- 1차: ContainerSync 전 즉시 캡처
    CaptureViewerPositions()

    -- 2차: Edit Mode 레이아웃이 늦게 적용될 수 있으므로 재시도
    C_Timer.After(2, function()
        if GroupSystem.enabled then
            CaptureViewerPositions()
        end
    end)

    -- [REPARENT] ContainerSync 초기화 (뷰어 훅 설치)
    if ContainerSync then
        ContainerSync:Initialize()
    end

    -- [DYNAMIC] DynamicIconBridge 초기화 (CustomIcons 레이아웃 억제)
    if DynamicIconBridge then
        DynamicIconBridge:Initialize()
    end

    -- [DYNAMIC] CustomIcons 그룹 → GroupSystem 동기화
    SyncDynamicGroups(gs)

    -- 콜백 등록
    CDMHookEngine:RegisterCallback(OnHookEngineUpdate)

    -- [FIX] 프록시 앵커 위치를 먼저 확정 (CreateGroupFrame 전에 호출)
    -- 프록시가 (0,0)인 상태에서 그룹 프레임이 생성되면 화면 중앙에 모이는 문제 해결
    -- RegisterGroupMovers → LoadMoverPosition → 프록시를 DB 저장 위치로 이동
    RegisterGroupMovers()

    -- 그룹 프레임 생성 (프록시가 이미 올바른 위치에 있으므로 정상 배치)
    if gs.groups then
        for groupName, groupSettings in pairs(gs.groups) do
            if groupSettings.enabled then
                GroupRenderer:CreateGroupFrame(groupName, groupSettings)
            end
        end
    end

    -- [FIX] 기존 CustomIcons 무버 정리 (GroupSystem이 통합 관리)
    if DDingUI.Movers and DDingUI.Movers.CreatedMovers then
        for moverName, holder in pairs(DDingUI.Movers.CreatedMovers) do
            if moverName:match("^DDingUI_DynGroup_") then
                if holder.mover then
                    holder.mover:Hide()
                    holder.mover:SetParent(nil)
                end
                DDingUI.Movers.CreatedMovers[moverName] = nil
            end
        end
    end

    -- Mover 등록 + 아이콘 렌더링 (CDM 아이콘 로드 완료 후)
    C_Timer.After(1.5, function()
        if GroupSystem.enabled then
            RegisterGroupMovers()
            -- [FIX] CDM 뷰어 참조 갱신 (리로드 후 뷰어가 재생성되었을 수 있음)
            if CDMHookEngine and CDMHookEngine.RefreshViewerRefs then
                CDMHookEngine:RefreshViewerRefs()
            end
            -- [FIX] CDM 뷰어에 Layout() 강제 호출 → 활성 버프 아이콘을 Show하도록 유도
            -- CDM은 리로드 직후 BuffIconCooldownViewer의 모든 아이콘을 Hide 상태로 시작
            -- Layout() 호출 시 CDM이 활성 버프를 재평가하여 Show() → OnShow 훅 → Reconcile
            for _, vName in pairs({"BuffIconCooldownViewer", "EssentialCooldownViewer", "UtilityCooldownViewer"}) do
                local v = _G[vName]
                if v then
                    if v.Layout then pcall(v.Layout, v) end
                end
            end
            -- CDM Layout 후 약간의 대기 (아이콘 Show 이벤트 처리 시간)
            C_Timer.After(0.2, function()
                if not GroupSystem.enabled then return end
                DoFullUpdate()
            end)
            -- [FIX] 폴링 활성화 — CDM 아이콘이 아직 Show 안 됐으면 OnShow 훅으로 감지
            if CDMHookEngine and CDMHookEngine.EnablePolling then
                CDMHookEngine:EnablePolling()
            end
            -- [FIX] Enable 완료 콜백: ResourceBars/CastBars가 프록시 위치 확정 후 Refresh
            if GroupSystem._onReadyCallback then
                local cb = GroupSystem._onReadyCallback
                GroupSystem._onReadyCallback = nil
                C_Timer.After(0, cb)
            end

            -- ★ T+3초: 최종 렌더링 보장 (CDM 뷰어 완전 안정화 후)
            C_Timer.After(1.5, function()
                if not GroupSystem.enabled then return end
                -- 뷰어 참조 다시 갱신 + CDM Layout 강제 + 최종 렌더링
                if CDMHookEngine and CDMHookEngine.RefreshViewerRefs then
                    CDMHookEngine:RefreshViewerRefs()
                end
                -- CDM Layout 다시 한번 강제 (완전 안정화 보장)
                local buffViewer = _G["BuffIconCooldownViewer"]
                if buffViewer and buffViewer.Layout then
                    pcall(buffViewer.Layout, buffViewer)
                end
                C_Timer.After(0.2, function()
                    if not GroupSystem.enabled then return end
                    DoFullUpdate()
                end)
            end)
        end
    end)


    -- [REPARENT] SkinAllIconsInViewer 훅 — 설정 패널에서 뷰어 옵션 변경 시
    -- 관리 아이콘(reparent)도 새 설정으로 재스키닝 + 레이아웃 갱신
    if DDingUI.IconViewers and DDingUI.IconViewers.SkinAllIconsInViewer and not self._skinHooked then
        self._skinHooked = true
        local pendingSkinRefresh = false
        hooksecurefunc(DDingUI.IconViewers, "SkinAllIconsInViewer", function()
            if not GroupSystem.enabled or pendingSkinRefresh then return end
            pendingSkinRefresh = true
            C_Timer.After(0.1, function()
                pendingSkinRefresh = false
                if GroupSystem.enabled then
                    -- [FIX] FlightHide 복원 중에는 앵커 재적용 없이 레이아웃만 갱신
                    -- Refresh()는 모든 그룹 프레임의 앵커를 DB 값으로 리셋하므로
                    -- Mover로 이동한 위치가 초기화되는 문제 발생
                    local fh = DDingUI.FlightHide
                    if fh and (fh.isActive or fh._restoring) then
                        GroupSystem:RefreshLayout()
                    else
                        GroupSystem:Refresh()
                    end
                end
            end)
        end)
    end

    -- [REPARENT] GROUP_ROSTER_UPDATE: 파티/레이드 상태 변경 시 groupOffsets 반영
    if not self._rosterHooked then
        self._rosterHooked = true
        local rosterFrame = CreateFrame("Frame")
        rosterFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
        local pendingRoster = false
        rosterFrame:SetScript("OnEvent", function()
            if not GroupSystem.enabled or pendingRoster then return end
            pendingRoster = true
            C_Timer.After(0.2, function()
                pendingRoster = false
                if GroupSystem.enabled then
                    DoFullUpdate()
                end
            end)
        end)
        self._rosterFrame = rosterFrame
    end

    -- 편집모드 연동 (ShowMovers/HideMovers 훅)
    if DDingUI.Movers and not self._moversHooked then
        self._moversHooked = true
        if DDingUI.Movers.ShowMovers then
            hooksecurefunc(DDingUI.Movers, "ShowMovers", function()
                if CDMHookEngine and GroupSystem.enabled then
                    CDMHookEngine:EnableEditModeClicks()
                    DoFullUpdate()
                    -- [FIX] 편집모드 후처리: ComputeEditModeSize로 정확한 크기 적용
                    if GroupRenderer and GroupRenderer.groupFrames and GroupRenderer.ComputeEditModeSize then
                        for gn, gFrame in pairs(GroupRenderer.groupFrames) do
                            local fw, fh = gFrame:GetSize()
                            if fw < 10 or fh < 10 then
                                local calcW, calcH = GroupRenderer:ComputeEditModeSize(gn)
                                if calcW and calcH then
                                    gFrame:SetSize(calcW, calcH)
                                    gFrame:Show()
                                end
                            end
                        end
                    end
                    -- [FIX] mover 크기 재동기화 (frame 크기 변경 반영)
                    for name, holder in pairs(DDingUI.Movers.CreatedMovers) do
                        if holder.parent and holder.mover and holder.mover:IsShown() then
                            local pw, ph = holder.parent:GetSize()
                            if pw and pw > 1 and ph and ph > 1 then
                                holder.mover:SetSize(pw, ph)
                            end
                        end
                    end
                end
            end)
        end
        if DDingUI.Movers.HideMovers then
            hooksecurefunc(DDingUI.Movers, "HideMovers", function()
                if CDMHookEngine and GroupSystem.enabled then
                    CDMHookEngine:DisableEditModeClicks()
                    -- [REPARENT] 편집모드 퇴장 → 즉시 재스캔 + 재배치
                    C_Timer.After(0.05, function()
                        if GroupSystem.enabled then
                            DoFullUpdate()
                        end
                    end)
                    -- [REPARENT] 안정화 패스: CDM이 지연 Layout 하는 경우 대비
                    C_Timer.After(0.5, function()
                        if GroupSystem.enabled then
                            DoFullUpdate()
                        end
                    end)
                end
            end)
        end
    end

    -- [FIX] 특성 변경/레벨업 시 그룹 프레임 앵커 재적용
    -- CDM이 뷰어를 재생성하면 그룹 프레임의 SetPoint anchor가 구 객체를 가리킴
    -- 뷰어 재생성 후 _G[attachTo]로 새 객체를 resolve하여 앵커 복구
    if not self._specChangeHooked then
        self._specChangeHooked = true
        local specFrame = CreateFrame("Frame")
        specFrame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
        specFrame:RegisterEvent("PLAYER_LEVEL_UP")
        specFrame:SetScript("OnEvent", function(_, event)
            if not GroupSystem.enabled then return end
            -- CDM이 뷰어를 재생성할 시간 대기 (FrameController보다 약간 뒤)
            C_Timer.After(2.0, function()
                if not GroupSystem.enabled then return end
                -- 그룹 프레임 앵커 재적용 → _G[attachTo]로 새 뷰어 resolve
                GroupSystem:Refresh()
                -- 매핑 모듈(시전바, 자원바 등) 위치도 재적용
                if DDingUI.Movers and DDingUI.Movers.ReloadMappedModulePositions then
                    DDingUI.Movers:ReloadMappedModulePositions()
                end
            end)
            -- 안정화 패스
            C_Timer.After(4.0, function()
                if not GroupSystem.enabled then return end
                GroupSystem:Refresh()
            end)
        end)
        self._specChangeFrame = specFrame
    end

    -- 초기 업데이트 (CDM이 Layout 완료 후)
    C_Timer.After(0.5, function()
        if GroupSystem.enabled then
            -- [FIX] DoFullUpdate() 대신 Refresh()를 호출하여 초기 로드 시 앵커 재적용 2차 패스까지 완벽 수행
            GroupSystem:Refresh()

            -- [FIX] 고아(orphan) 동적 아이콘 클린업 — 이전 코드의 불완전한 삭제로 화면에 남아있는 프레임 제거
            C_Timer.After(0.5, function()
                if not GroupSystem.enabled then return end
                CleanupOrphanedDynamicIcons()
            end)

            -- [REPARENT] reparent 후 쿨다운 폰트 재적용
            C_Timer.After(0.2, function()
                if GroupSystem.enabled and DDingUI.ReapplyCooldownFonts then
                    DDingUI.ReapplyCooldownFonts()
                end
            end)
        end
    end)
end

function GroupSystem:Disable()
    if not self.enabled then return end

    self.enabled = false

    -- CDM 아이콘 원래 상태 복원
    if GroupRenderer then
        GroupRenderer:RestoreAllIcons()
        GroupRenderer:DestroyAllGroups()
    end

    -- [REPARENT] GROUP_ROSTER_UPDATE 이벤트 해제
    if self._rosterFrame then
        self._rosterFrame:UnregisterAllEvents()
    end

    -- [DYNAMIC] DynamicIconBridge 종료 (CustomIcons 레이아웃 복원)
    if DynamicIconBridge then
        DynamicIconBridge:Shutdown()
    end

    -- [REPARENT] CDM 뷰어 복원 (은닉 해제)
    if ContainerSync then
        ContainerSync:Shutdown()
    end

    -- CDMHookEngine 종료
    if CDMHookEngine then
        CDMHookEngine:Shutdown()
    end

    -- CDM 뷰어 원래 Layout 트리거 (아이콘 원래 위치로)
    C_Timer.After(0.1, function()
        TriggerCDMRelayout()
    end)
end

function GroupSystem:Toggle()
    local gs = GetSettings()
    if not gs then return end

    if gs.enabled then
        self:Enable()
    else
        self:Disable()
    end
end

-- ============================================================
-- 새로고침 (설정 변경 시)
-- ============================================================

function GroupSystem:Refresh()
    if not self.enabled then return end

    -- [FIX] 그룹 프레임 앵커 재적용 (attachTo/anchorPoint 변경 반영)
    -- CreateGroupFrame은 기존 프레임을 스킵하므로, 설정 변경 시 여기서 재적용
    local gs = GetSettings()
    if gs and gs.groups and GroupRenderer and GroupRenderer.groupFrames then
        -- [FIX] 다중 그룹간 앵커 연결 시 pairs 무작위 순서로 인한 앵커 대상 미발견 문제 해결
        -- 1차 패스: 모든 활성화된 그룹 프레임을 사전 생성 (물리적 존재 보장)
        for groupName, groupSettings in pairs(gs.groups) do
            if groupSettings.enabled then
                GroupRenderer:CreateGroupFrame(groupName, groupSettings)
            end
        end

        -- 2차 패스: 모든 프레임이 생성된 후 앵커 적용
        for groupName, groupSettings in pairs(gs.groups) do
            local frame = GroupRenderer.groupFrames[groupName]
            if frame and groupSettings.enabled then
                -- [FIX] 3대 핵심 그룹은 자신의 프록시를 무조건 따라가게 설정
                local CORE_PROXY = {
                    ["Cooldowns"] = "DDingUI_Anchor_Cooldowns",
                    ["Buffs"]     = "DDingUI_Anchor_Buffs",
                    ["Utility"]   = "DDingUI_Anchor_Utility",
                }
                local proxyName = CORE_PROXY[groupName]
                local proxyFrame = proxyName and _G[proxyName]
                
                local attachTo = groupSettings.attachTo or "UIParent"
                local anchorFrame = _G[attachTo] or UIParent
                local selfPoint = groupSettings.selfPoint or "CENTER"  -- [FIX] DB 저장값 사용
                
                frame:ClearAllPoints()
                if proxyFrame then
                    frame:SetPoint("CENTER", proxyFrame, "CENTER", 0, 0)
                else
                    frame:SetPoint(
                        selfPoint,
                        anchorFrame,
                        groupSettings.anchorPoint or "CENTER",
                        groupSettings.offsetX or 0,
                        groupSettings.offsetY or 0
                    )
                end
                -- Mover도 새 앵커 위치로 갱신
                local moverName = "DDingUI_Group_" .. groupName
                if DDingUI.Movers and DDingUI.Movers.CreatedMovers then
                    local holder = DDingUI.Movers.CreatedMovers[moverName]
                    if holder and holder.mover then
                        holder.mover:ClearAllPoints()
                        holder.mover:SetPoint(selfPoint, anchorFrame, groupSettings.anchorPoint or "CENTER",
                            groupSettings.offsetX or 0, groupSettings.offsetY or 0)
                        local fw, fh = frame:GetSize()
                        if fw and fw > 1 and fh and fh > 1 then
                            holder.mover:SetSize(fw, fh)
                        end
                    end
                end
            end
        end
    end

    -- [FIX] 설정 변경 시 강제 재설정 (SkinIcon + SetupFrameInContainer 재실행)
    GroupRenderer._forceFullSetup = true
    DoFullUpdate()
    GroupRenderer._forceFullSetup = false
    -- DoFullUpdate 내부에서 ContainerSync:SyncAll() 이미 호출됨

    -- Mover 업데이트
    RegisterGroupMovers()

    -- [FIX] 동적 그룹 프레임 → Mover 위치 동기화
    -- MoverToModuleMapping 등록 프레임은 UpdateParentPosition이 스킵되므로
    -- Mover가 LoadMoverPosition으로 올바른 위치에 있어도 그룹 프레임은 미갱신
    if DDingUI.Movers and DDingUI.Movers.CreatedMovers and gs and gs.groups then
        for groupName, groupSettings in pairs(gs.groups) do
            if groupSettings.enabled and not ({["Cooldowns"]=1,["Buffs"]=1,["Utility"]=1})[groupName] then
                local moverName = "DDingUI_Group_" .. groupName
                local holder = DDingUI.Movers.CreatedMovers[moverName]
                local frame = GroupRenderer and GroupRenderer.groupFrames and GroupRenderer.groupFrames[groupName]
                if holder and holder.mover and frame then
                    local point, anchor, relPoint, x, y = holder.mover:GetPoint(1)
                    if point then
                        frame:ClearAllPoints()
                        frame:SetPoint(point, anchor or UIParent, relPoint or point, x or 0, y or 0)
                    end
                end
            end
        end
    end

    -- [FIX] _forceFullSetup으로 아이콘 re-skin 후 AssistHighlight glow가 Clear됨
    -- Refresh 완료 후 보조 강조 효과 재적용
    if DDingUI.AssistHighlight and DDingUI.AssistHighlight.UpdateAllHighlights then
        C_Timer.After(0.1, function()
            DDingUI.AssistHighlight:UpdateAllHighlights()
        end)
    end
end

-- [12.0.1] 레이아웃만 갱신 (아이콘 크기/간격/방향 변경 시)
-- _forceFullSetup 없이 DoFullUpdate → LayoutGroup이 SetIconSize로 아이콘 크기 갱신
-- SetupFrameInContainer + SkinIcon 스킵 → 깜빡임 없음
function GroupSystem:RefreshLayout()
    if not self.enabled then return end
    DoFullUpdate()
end

-- 그룹 추가 후 새로고침
function GroupSystem:OnGroupAdded(groupName)
    if not self.enabled then return end

    local gs = GetSettings()
    if not gs then return end
    local groupSettings = gs.groups and gs.groups[groupName]
    if not groupSettings then return end

    GroupRenderer:CreateGroupFrame(groupName, groupSettings)
    RegisterGroupMovers()
    DoFullUpdate()
end

-- 그룹 삭제 후 정리
function GroupSystem:OnGroupDeleted(groupName, passedSourceKey)
    -- [FIX] 다이나믹 그룹이면 CustomIcons 원본도 정리 (고스트 프레임 방지)
    local gs = GetSettings()
    -- passedSourceKey: 호출자가 DeleteGroup 전에 미리 캡처한 값 (DB 삭제 후에는 조회 불가)
    local sourceKey = passedSourceKey
    if gs and not sourceKey then
        -- fallback: DB에서 읽기 (아직 삭제되지 않은 경우)
        local grpInfo = gs.groups and gs.groups[groupName]
        if grpInfo and grpInfo.sourceGroupKey then
            sourceKey = grpInfo.sourceGroupKey
        end
        -- dyn_ 접두사 매칭 (legacy)
        if not sourceKey then
            sourceKey = groupName:match("^dyn_(.+)$")
        end
    end
    if sourceKey then
        local ci = DDingUI.CustomIcons
        if ci and ci.RemoveGroup then
            ci:RemoveGroup(sourceKey)
        end
        -- [FIX] CustomIcons 네이티브 컨테이너 명시적 숨기기 (고스트 아이콘 방지)
        if ci and ci.GetGroupFrames then
            local groupFrames = ci:GetGroupFrames()
            if groupFrames then
                local container = groupFrames[sourceKey]
                if container then
                    local children = { container:GetChildren() }
                    for _, child in ipairs(children) do
                        child:Hide()
                    end
                    container:Hide()
                end
            end
        end
    end

    -- [FIX] 프레임/mover는 항상 정리 (enabled 여부 무관 — stale 프레임 방지)
    GroupRenderer:DestroyGroup(groupName)

    if not self.enabled then return end

    -- 삭제된 그룹의 아이콘을 다른 그룹으로 재분류
    DoFullUpdate()
    -- DoFullUpdate 내부에서 ContainerSync:SyncAll() 이미 호출됨

    -- CDM 원래 Layout 트리거 (미관리 아이콘 복원)
    C_Timer.After(0.1, function()
        TriggerCDMRelayout()
        -- [REPARENT] Layout 후 뷰어 상태 재평가
        if ContainerSync then
            C_Timer.After(0.2, function()
                ContainerSync:SyncAll()
            end)
        end
        -- [FIX] 삭제 후 고아 프레임 클린업 (삭제 로직에서 누락된 프레임 정리)
        C_Timer.After(0.3, function()
            if GroupSystem.enabled then
                CleanupOrphanedDynamicIcons()
                -- [FIX] sourceKey에 해당하는 모든 프레임 추가 Hide 패스
                if sourceKey then
                    local iconFrames = {}
                    local ci = DDingUI.CustomIcons
                    if ci and ci.GetAllIconFrames then
                        iconFrames = ci:GetAllIconFrames()
                    end
                    local dynDB = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.dynamicIcons
                    if dynDB then
                        -- 삭제된 그룹의 아이콘들 숨기기
                        local group = dynDB.groups and dynDB.groups[sourceKey]
                        if group and group.icons then
                            for _, iconKey in ipairs(group.icons) do
                                local frame = iconFrames[iconKey]
                                if frame and frame.Hide then
                                    frame:Hide()
                                end
                            end
                        end
                    end
                end
            end
        end)
    end)
end

-- ============================================================
-- 초기화 (PLAYER_ENTERING_WORLD)
-- ============================================================

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", function(self, event, isInitialLogin, isReloadingUI)
    if event == "PLAYER_ENTERING_WORLD" then
        -- [FIX] 로딩 지연(3초) 대기 중에 기본 CDM 뷰어가 나타나 기본 위치에 나열되는 것을 방지
        -- 화면에 "잠깐 나왔다가 사라짐" 현상 해결
        local gsDB = DDingUI_DB and DDingUI_DB.profile and DDingUI_DB.profile.groupSystem
        if not gsDB or (gsDB.enabled ~= false and gsDB.hideDefaultViewers ~= false) then
            -- [FIX] 3초 대기 중 CustomIcons 레이아웃도 미리 억제
            if DDingUI.DynamicIconBridge and DDingUI.DynamicIconBridge.SuppressCustomIconsLayout then
                DDingUI.DynamicIconBridge:SuppressCustomIconsLayout()
            end
            
            local enforceTicks = 0
            local enforceFrame = CreateFrame("Frame")
            enforceFrame:SetScript("OnUpdate", function(self, elapsed)
                enforceTicks = enforceTicks + elapsed
                if enforceTicks > 4.0 then
                    self:SetScript("OnUpdate", nil)
                    return
                end
                for _, viewerName in pairs({"EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer"}) do
                    local viewer = _G[viewerName]
                    if viewer and viewer.GetAlpha and viewer:GetAlpha() > 0.01 then
                        viewer:SetAlpha(0)
                    end
                end
                
                -- [FIX] CustomIcons native 컨테이너도 숨김 강제 적용
                local ci = DDingUI.CustomIcons
                if ci and ci.GetGroupFrames then
                    local gf = ci:GetGroupFrames()
                    if gf then
                        for _, cont in pairs(gf) do
                            if cont.GetAlpha and cont:GetAlpha() > 0.01 then
                                cont:SetAlpha(0)
                            end
                        end
                    end
                end
            end)
        end

        -- DDingUI DB가 준비될 때까지 대기
        C_Timer.After(3, function()
            if not DDingUI.db then return end

            GroupSystem.initialized = true

            -- [DYNAMIC] 아이콘 그룹 무조건 활성화
            local gs = GetSettings()
            if gs then
                gs.enabled = true
                GroupSystem:Enable()
            end

            -- [FIX] 리로드 후 버프(아이콘)가 보이지 않는 현상 해결
            -- 편집모드를 나갈 때 발생하는 이벤트(ForceReconcile + SyncAll)를
            -- 로딩 후 안정화 단계에서 한 번 강제로 발생시켜 뷰어/아이콘 렌더링을 완전히 확정 지음 (유저 제안)
            C_Timer.After(1.5, function()
                local fc = DDingUI.FrameController or DDingUI.CDMHookEngine
                if fc and fc.ForceReconcile then
                    fc:ForceReconcile()
                end
            end)
            C_Timer.After(2.0, function()
                if DDingUI.ContainerSync then
                    DDingUI.ContainerSync:SyncAll()
                end
                -- 그룹 프레임 앵커 갱신
                if GroupSystem.RefreshLayout then
                    GroupSystem:RefreshLayout()
                end
            end)
        end)

        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    end
end)

-- ============================================================
-- [DIAG] /ddgs 진단 커맨드 — 2줄/이빠짐 디버깅용
-- ============================================================

SLASH_DDGS1 = "/ddgs"
SlashCmdList["DDGS"] = function(msg)
    local p = print
    p("|cff00ffff=== DDingUI GroupSystem Diagnostic ===|r")
    p("GroupSystem.enabled:", GroupSystem.enabled)
    p("GroupSystem.initialized:", GroupSystem.initialized)

    -- ContainerSync 상태
    local cs = DDingUI.ContainerSync
    if cs then
        for _, vn in pairs({"EssentialCooldownViewer", "BuffIconCooldownViewer", "UtilityCooldownViewer"}) do
            local hidden = cs._isViewerHidden and cs._isViewerHidden(vn) or false
            local viewer = _G[vn]
            local isShown = viewer and viewer:IsShown() or false
            local vw, vh = 0, 0
            if viewer then vw, vh = viewer:GetSize() end
            p("  " .. vn .. ": hidden=" .. tostring(hidden) .. " IsShown=" .. tostring(isShown)
                .. " size=" .. math.floor(vw) .. "x" .. math.floor(vh))
        end
    else
        p("  ContainerSync: nil")
    end

    -- CDM 뷰어별 아이콘 카운트
    local fc = DDingUI.FrameController or DDingUI.CDMHookEngine
    if fc then
        for _, vn in pairs({"EssentialCooldownViewer", "BuffIconCooldownViewer", "UtilityCooldownViewer"}) do
            local viewer = _G[vn]
            if viewer and viewer.itemFramePool then
                local total, managed, shown, children = 0, 0, 0, 0
                for icon in viewer.itemFramePool:EnumerateActive() do
                    total = total + 1
                    if icon._ddIsManaged then managed = managed + 1 end
                    if icon:IsShown() then shown = shown + 1 end
                end
                -- GetChildren으로 현재 자식 수 확인 (reparent 후 줄어야 함)
                local ch = { viewer:GetChildren() }
                for _, c in ipairs(ch) do
                    if c and (c.Icon or c.icon) and c:IsShown() then
                        children = children + 1
                    end
                end
                p("  " .. vn .. " pool: total=" .. total .. " managed=" .. managed
                    .. " shown=" .. shown .. " visibleChildren=" .. children)
            end
        end
    end

    -- 그룹 프레임 상태
    local gr = DDingUI.GroupRenderer
    if gr and gr.groupFrames then
        p("|cff88ff88--- Group Frames ---|r")
        for gn, frame in pairs(gr.groupFrames) do
            local shown = frame:IsShown()
            local iconCount = frame._iconCount or 0
            local visCount = 0
            if frame._managedIcons then
                for i = 1, iconCount do
                    local ic = frame._managedIcons[i]
                    if ic and ic:IsShown() then visCount = visCount + 1 end
                end
            end
            local fw, fh = frame:GetSize()
            local cx, cy = frame:GetCenter()
            p("  [" .. gn .. "] shown=" .. tostring(shown)
                .. " icons=" .. iconCount .. " visible=" .. visCount
                .. " size=" .. math.floor(fw + 0.5) .. "x" .. math.floor(fh + 0.5)
                .. " pos=" .. math.floor((cx or 0) + 0.5) .. "," .. math.floor((cy or 0) + 0.5))

            -- 각 아이콘의 부모/위치 확인
            if frame._managedIcons and visCount > 0 then
                for i = 1, math.min(iconCount, 5) do
                    local ic = frame._managedIcons[i]
                    if ic then
                        local parent = ic:GetParent()
                        local parentMatch = (parent == frame) and "OK" or "MISMATCH!"
                        local pt, relTo, relPt, ox, oy = ic:GetPoint(1)
                        p("    icon[" .. i .. "] parent=" .. parentMatch
                            .. " shown=" .. tostring(ic:IsShown())
                            .. " pt=" .. tostring(pt) .. " x=" .. math.floor((ox or 0) + 0.5)
                            .. " y=" .. math.floor((oy or 0) + 0.5))
                    end
                end
            end
        end
    end

    -- 설정 값 확인
    local gs = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.groupSystem
    if gs then
        p("|cff88ff88--- Settings ---|r")
        p("  gs.enabled:", gs.enabled)
        p("  gs.autoClassify:", gs.autoClassify)
        if gs.groups then
            for gn, gset in pairs(gs.groups) do
                p("  [" .. gn .. "] enabled=" .. tostring(gset.enabled)
                    .. " rowLimit=" .. tostring(gset.rowLimit)
                    .. " autoFilter=" .. tostring(gset.autoFilter)
                    .. " dir=" .. tostring(gset.direction)
                    .. " type=" .. tostring(gset.groupType or "cdm")
                    .. (gset.sourceGroupKey and (" src=" .. tostring(gset.sourceGroupKey)) or ""))
            end
        end
    end

    -- 뷰어 설정
    local vs = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.viewers
    if vs and vs["BuffIconCooldownViewer"] then
        local bvs = vs["BuffIconCooldownViewer"]
        p("|cff88ff88--- BuffIconCooldownViewer Settings ---|r")
        p("  rowLimit=" .. tostring(bvs.rowLimit)
            .. " primaryDir=" .. tostring(bvs.primaryDirection)
            .. " secondaryDir=" .. tostring(bvs.secondaryDirection)
            .. " iconSize=" .. tostring(bvs.iconSize)
            .. " spacing=" .. tostring(bvs.spacing))
    end

    p("|cff00ffff=== End Diagnostic ===|r")

    -- [DIAG] DynamicIconBridge 상태
    local bridge = DDingUI.DynamicIconBridge
    if bridge then
        p("|cff88ff88--- DynamicIconBridge ---|r")
        p("  IsActive:", bridge:IsActive())
        local ci = DDingUI.CustomIcons
        if ci and ci.GetAllIconFrames then
            local allFrames = ci:GetAllIconFrames()
            local frameCount = 0
            for _ in pairs(allFrames) do frameCount = frameCount + 1 end
            p("  runtime.iconFrames count:", frameCount)
        end
        local dynDB = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.dynamicIcons
        if dynDB then
            p("  dynDB.groups:")
            for gk, grp in pairs(dynDB.groups or {}) do
                local iconCount = grp.icons and #grp.icons or 0
                p("    [" .. gk .. "] name=" .. tostring(grp.name) .. " icons=" .. iconCount .. " enabled=" .. tostring(grp.enabled ~= false))
            end
            -- 각 동적 그룹의 GetActiveIconsForGroup 결과
            if gs and gs.groups then
                for gn, gset in pairs(gs.groups) do
                    if gset.groupType == "dynamic" and gset.sourceGroupKey then
                        local activeIcons = bridge:GetActiveIconsForGroup(gset.sourceGroupKey)
                        p("  GetActiveIcons[" .. gn .. " -> " .. gset.sourceGroupKey .. "]: " .. #activeIcons .. " icons")
                        for _, entry in ipairs(activeIcons) do
                            local f = entry.frame
                            p("    " .. entry.iconKey .. " frame=" .. tostring(f ~= nil)
                                .. " shown=" .. tostring(f and f:IsShown())
                                .. " managed=" .. tostring(f and f._ddIsManaged))
                        end
                    end
                end
            end
        end
    end
end
