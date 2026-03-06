-- [GROUP SYSTEM] DynamicIconBridge: CustomIcons ↔ GroupSystem 통합 어댑터
-- [DYNAMIC] CustomIcons(생석치물물약) 프레임을 GroupSystem 컨테이너에서 관리
-- FrameController 패턴 기반 — reparent to UIParent, container 앵커 참조
local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
if not DDingUI then return end

local DynamicIconBridge = {}
DDingUI.DynamicIconBridge = DynamicIconBridge

-- ============================================================
-- Locals
-- ============================================================

local pairs = pairs
local ipairs = ipairs
local wipe = wipe
local tostring = tostring
local hooksecurefunc = hooksecurefunc
local C_Timer = C_Timer
local CreateFrame = CreateFrame

-- ============================================================
-- State
-- ============================================================

local managedFrames = {}    -- [iconKey] = true
local initialized = false
local layoutSuppressed = false

-- ============================================================
-- CustomIcons 접근 헬퍼
-- ============================================================

local function GetCustomIcons()
    return DDingUI.CustomIcons
end

-- CustomIcons.lua의 runtime.iconFrames에 접근
-- CustomIcons:GetAllIconFrames() API를 통해 접근 (Phase 5에서 추가)
local function GetIconFrames()
    local ci = GetCustomIcons()
    if ci and ci.GetAllIconFrames then
        return ci:GetAllIconFrames()
    end
    return {}
end

-- CustomIcons DB 접근
local function GetDynamicDB()
    local profile = DDingUI.db and DDingUI.db.profile
    if not profile then return nil end
    profile.dynamicIcons = profile.dynamicIcons or {}
    local db = profile.dynamicIcons
    db.iconData = db.iconData or {}
    db.ungrouped = db.ungrouped or {}
    db.groups = db.groups or {}
    return db
end

-- ============================================================
-- 활성 아이콘 수집
-- ============================================================

-- ShouldIconSpawn 간이 버전 (CustomIcons의 로직 참조)
local function IsIconActive(iconKey, iconData, iconFrame)
    if not iconData then return false end
    if not iconFrame then return false end

    -- spellbook 체크: spell 타입이면 배운 주문만
    if iconData.type == "spell" and iconData.id then
        local spellInfo = C_Spell and C_Spell.GetSpellInfo(iconData.id)
        if not spellInfo then return false end
    end

    -- loadConditions 체크
    local settings = iconData.settings
    if settings and settings.loadConditions and settings.loadConditions.enabled then
        local lc = settings.loadConditions
        -- Spec 조건
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
        -- Combat 조건
        if lc.inCombat and not InCombatLockdown() then return false end
        if lc.outOfCombat and InCombatLockdown() then return false end
    end

    return true
end

-- GroupSystem에서 호출: 특정 CustomIcons 그룹의 활성 아이콘 목록 반환
-- sourceGroupKey: CustomIcons의 그룹 키 ("group_xxx" 또는 "ungrouped")
-- 반환: { {iconKey=string, frame=Frame, iconData=table}, ... }
function DynamicIconBridge:GetActiveIconsForGroup(sourceGroupKey)
    if not initialized then return {} end

    local ci = GetCustomIcons()
    if not ci then return {} end

    local db = GetDynamicDB()
    if not db then return {} end

    local iconFrames = GetIconFrames()

    -- 대상 아이콘 키 수집
    local targetKeys = {}
    if sourceGroupKey == "ungrouped" then
        for iconKey in pairs(db.ungrouped or {}) do
            targetKeys[iconKey] = true
        end
    else
        local group = db.groups and db.groups[sourceGroupKey]
        if group and group.icons then
            for _, iconKey in ipairs(group.icons) do
                targetKeys[iconKey] = true
            end
        end
    end

    -- 활성 아이콘 필터링
    local result = {}
    for iconKey in pairs(targetKeys) do
        local frame = iconFrames[iconKey]
        local iconData = db.iconData[iconKey]
        if frame and iconData and IsIconActive(iconKey, iconData, frame) then
            result[#result + 1] = {
                iconKey = iconKey,
                frame = frame,
                iconData = iconData,
            }
        end
    end

    -- 정렬: 그룹 내 순서 유지
    if sourceGroupKey ~= "ungrouped" then
        local group = db.groups and db.groups[sourceGroupKey]
        if group and group.icons then
            local orderMap = {}
            for i, k in ipairs(group.icons) do
                orderMap[k] = i
            end
            table.sort(result, function(a, b)
                return (orderMap[a.iconKey] or 9999) < (orderMap[b.iconKey] or 9999)
            end)
        end
    else
        -- ungrouped: iconKey 알파벳 순
        table.sort(result, function(a, b)
            return a.iconKey < b.iconKey
        end)
    end

    return result
end

-- CustomIcons 그룹 목록 반환 (GroupSystem 동기화용)
-- 반환: { [sourceGroupKey] = {name=string, enabled=boolean, iconCount=number}, ... }
function DynamicIconBridge:GetDynamicGroups()
    local db = GetDynamicDB()
    if not db then return {} end

    local result = {}

    -- 사용자 정의 그룹
    for groupKey, group in pairs(db.groups or {}) do
        result[groupKey] = {
            name = group.name or groupKey,
            enabled = group.enabled ~= false,
            iconCount = group.icons and #group.icons or 0,
        }
    end

    -- ungrouped 아이콘이 있으면 포함
    local ungroupedCount = 0
    for _ in pairs(db.ungrouped or {}) do
        ungroupedCount = ungroupedCount + 1
    end
    if ungroupedCount > 0 then
        result["ungrouped"] = {
            name = "Ungrouped",
            enabled = true,
            iconCount = ungroupedCount,
        }
    end

    return result
end

-- [FIX] zoom + 종횡비 크롭을 결합한 TexCoord 적용
-- CustomIcons의 ApplyAspectRatioCrop과 동일한 로직
function DynamicIconBridge.ApplyTexCoordCrop(texture, zoom, aspectRatio)
    if not texture or not texture.SetTexCoord then return end
    zoom = zoom or 0.08
    aspectRatio = aspectRatio or 1.0
    if aspectRatio <= 0 then aspectRatio = 1.0 end

    local left, right, top, bottom = zoom, 1 - zoom, zoom, 1 - zoom
    local regionW = right - left
    local regionH = bottom - top

    if regionW > 0 and regionH > 0 and aspectRatio ~= 1.0 then
        local currentRatio = regionW / regionH
        if aspectRatio > currentRatio then
            local desiredH = regionW / aspectRatio
            local cropH = (regionH - desiredH) / 2
            top = top + cropH
            bottom = bottom - cropH
        elseif aspectRatio < currentRatio then
            local desiredW = regionH * aspectRatio
            local cropW = (regionW - desiredW) / 2
            left = left + cropW
            right = right - cropW
        end
    end

    texture:SetTexCoord(left, right, top, bottom)
end

-- ============================================================
-- 프레임 컨테이너 관리 (FrameController 패턴)
-- ============================================================

function DynamicIconBridge:SetupFrameInContainer(frame, container, targetW, targetH, iconKey, zoom, aspectRatioCrop)
    if not frame or not container then return end

    -- 1. 원래 상태 저장 (최초 1회)
    if not frame._ddOrigState then
        frame._ddOrigState = {
            parent = frame:GetParent(),
            width = frame:GetWidth(),
            height = frame:GetHeight(),
            scale = frame:GetScale(),
            points = {},
        }
        local numPoints = frame:GetNumPoints()
        for i = 1, numPoints do
            local point, relTo, relPoint, x, y = frame:GetPoint(i)
            frame._ddOrigState.points[i] = { point, relTo, relPoint, x, y }
        end
    end

    -- 2. SetParent(UIParent) + 컨테이너 참조 -- [DYNAMIC]
    frame:SetParent(UIParent)
    frame._ddContainerRef = container
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(container:GetFrameLevel() + 10)

    -- 3. 스케일 강제 1
    frame:SetScale(1)

    -- 4. 타겟 크기 설정
    frame._ddTargetWidth = targetW
    frame._ddTargetHeight = targetH
    frame._ddSettingSize = true
    frame:SetSize(targetW, targetH)
    frame._ddSettingSize = false

    -- 아이콘 텍스처: zoom + 종횡비 크롭을 TexCoord에 결합
    if frame.icon then
        zoom = zoom or 0.08
        frame.icon:SetAllPoints(frame)
        DynamicIconBridge.ApplyTexCoordCrop(frame.icon, zoom, aspectRatioCrop or 1.0)
    end

    -- 5. 관리 태그
    frame._ddIsManaged = true
    frame._ddIconKey = iconKey

    -- [FIX] reparent 후 명시적 Show (이전 부모가 숨겨졌으면 프레임도 숨겨진 상태)
    frame:Show()

    -- [FIX] SetSize snap-back 훅 설치 (CustomIcons가 네이티브 크기로 되돌리는 것 방지)
    -- FrameController.InstallFrameHooks 패턴과 동일 — 비행 숨기기 후 복원 시 납작해짐 방지
    if not frame._ddBridgeSizeHooked then
        local issecretvalue = issecretvalue
        local math_abs = math.abs
        hooksecurefunc(frame, "SetSize", function(self, w, h)
            if self._ddSettingSize then return end
            if not self._ddIsManaged then return end
            if issecretvalue and (issecretvalue(w) or issecretvalue(h)) then return end
            local tw = self._ddTargetWidth
            local th = self._ddTargetHeight
            if tw and th then
                local dw = math_abs((w or 0) - tw)
                local dh = math_abs((h or 0) - th)
                if dw > 0.5 or dh > 0.5 then
                    self._ddSettingSize = true
                    self:SetSize(tw, th)
                    self._ddSettingSize = false
                end
            end
        end)
        frame._ddBridgeSizeHooked = true
    end

    -- [FIX] ClearAllPoints snap-back 훅 (FrameController 패턴과 동일)
    -- 비행 숨기 복원 시 CustomIcons가 위치를 초기화하는 것 방지
    if not frame._ddBridgeClearPointsHooked then
        hooksecurefunc(frame, "ClearAllPoints", function(self)
            if self._ddSettingPosition then return end
            if not self._ddIsManaged then return end
            local cont = self._ddContainerRef
            if cont and self._ddTargetPoint then
                self._ddSettingPosition = true
                self:SetPoint(
                    self._ddTargetPoint,
                    cont,
                    self._ddTargetRelPoint or "CENTER",
                    self._ddTargetX or 0,
                    self._ddTargetY or 0
                )
                self._ddSettingPosition = false
            end
        end)
        frame._ddBridgeClearPointsHooked = true
    end

    -- [FIX] SetPoint snap-back 훅 (FrameController 패턴과 동일)
    -- 외부 코드가 위치를 변경하면 GroupRenderer가 설정한 위치로 복원
    if not frame._ddBridgeSetPointHooked then
        hooksecurefunc(frame, "SetPoint", function(self)
            if self._ddSettingPosition then return end
            if not self._ddIsManaged then return end
            local cont = self._ddContainerRef
            if not cont then return end
            if not self._ddTargetPoint then return end
            self._ddSettingPosition = true
            self:ClearAllPoints()
            self:SetPoint(
                self._ddTargetPoint,
                cont,
                self._ddTargetRelPoint or "CENTER",
                self._ddTargetX or 0,
                self._ddTargetY or 0
            )
            self._ddSettingPosition = false
        end)
        frame._ddBridgeSetPointHooked = true
    end

    -- 6. 초기 위치 (CENTER, GroupRenderer의 LayoutGroup이 최종 위치 설정)
    if not frame._ddTargetPoint then
        frame._ddTargetPoint = "CENTER"
        frame._ddTargetRelPoint = "CENTER"
        frame._ddTargetX = 0
        frame._ddTargetY = 0
    end

    frame._ddSettingPosition = true
    frame:ClearAllPoints()
    frame:SetPoint(
        frame._ddTargetPoint,
        container,
        frame._ddTargetRelPoint or "CENTER",
        frame._ddTargetX or 0,
        frame._ddTargetY or 0
    )
    frame._ddSettingPosition = false

    -- 7. Show
    if container:IsShown() then
        frame:Show()
    else
        frame:Hide()
    end

    -- [FIX] FlightHide 활성 중이면 새 아이콘도 알파 0 적용
    local fh = DDingUI.FlightHide
    if fh and fh.isActive then
        frame:SetAlpha(0)
    end

    managedFrames[iconKey] = true
end

function DynamicIconBridge:ReleaseFrame(frame, iconKey)
    if not frame then return end

    local orig = frame._ddOrigState
    if orig then
        -- [FIX] 이미 부모가 nil (RemoveGroup에서 정리됨)이면 복원하지 않음 (고스트 프레임 방지)
        if orig.parent and frame:GetParent() ~= nil then
            frame:SetParent(orig.parent)
        end
        if frame:GetParent() ~= nil then
            frame:SetSize(orig.width, orig.height)
            frame:SetScale(orig.scale)
        end
    end

    -- 관리 태그 정리
    frame._ddTargetPoint = nil
    frame._ddTargetRelPoint = nil
    frame._ddTargetX = nil
    frame._ddTargetY = nil
    frame._ddTargetWidth = nil
    frame._ddTargetHeight = nil
    frame._ddIsManaged = nil
    frame._ddContainerRef = nil
    frame._ddIconKey = nil
    frame._ddOrigState = nil

    if iconKey then
        managedFrames[iconKey] = nil
    end

    -- [FIX] 해제된 프레임 명시적 숨기기 (원래 부모로 복원 후에도 화면에 남는 고스트 방지)
    if frame.Hide then
        frame:Hide()
    end
end

function DynamicIconBridge:ReleaseAllFrames()
    local iconFrames = GetIconFrames()
    for iconKey in pairs(managedFrames) do
        local frame = iconFrames[iconKey]
        if frame then
            self:ReleaseFrame(frame, iconKey)
        end
    end
    wipe(managedFrames)
end

function DynamicIconBridge:IsFrameManaged(iconKey)
    return managedFrames[iconKey] == true
end

-- ============================================================
-- CustomIcons 레이아웃 억제
-- ============================================================

function DynamicIconBridge:IsActive()
    return initialized and layoutSuppressed
end

function DynamicIconBridge:SuppressCustomIconsLayout()
    layoutSuppressed = true
end

function DynamicIconBridge:RestoreCustomIconsLayout()
    if not layoutSuppressed then return end
    layoutSuppressed = false

    -- 복원 후 CustomIcons가 자체 레이아웃을 재실행하도록 트리거
    local ci = GetCustomIcons()
    if ci and ci.LoadDynamicIcons then
        C_Timer.After(0.1, function()
            ci:LoadDynamicIcons()
        end)
    end
end

-- ============================================================
-- 초기화 / 종료
-- ============================================================

function DynamicIconBridge:Initialize()
    if initialized then return end
    initialized = true

    -- CustomIcons가 로드되지 않았으면 대기
    local ci = GetCustomIcons()
    if not ci then
        -- CustomIcons 로드 대기 (1초 후 재시도)
        C_Timer.After(1, function()
            if initialized and not GetCustomIcons() then
                -- CustomIcons 없으면 Bridge 비활성
                initialized = false
            end
        end)
        return
    end

    -- 레이아웃 억제 시작
    self:SuppressCustomIconsLayout()
end

function DynamicIconBridge:Shutdown()
    if not initialized then return end
    initialized = false

    -- 모든 managed 프레임 복원
    self:ReleaseAllFrames()

    -- CustomIcons 레이아웃 복원
    self:RestoreCustomIconsLayout()
end

-- ============================================================
-- GroupSystem 업데이트 트리거 (CustomIcons 이벤트 → GroupSystem 재레이아웃)
-- ============================================================

-- CustomIcons의 이벤트 핸들러 후에 GroupSystem도 업데이트하도록 훅
-- GroupInit.DoFullUpdate가 이미 주기적으로 호출되므로,
-- 추가 트리거는 CustomIcons 아이콘 추가/삭제 시에만 필요
function DynamicIconBridge:NotifyIconsChanged()
    if not initialized then return end
    if not layoutSuppressed then return end

    -- DoFullUpdate 트리거 (디바운스)
    if self._updatePending then return end
    self._updatePending = true

    C_Timer.After(0.2, function()
        self._updatePending = false
        if not initialized then return end

        -- GroupInit의 DoFullUpdate 호출
        local gs = DDingUI.GroupSystem
        if gs and gs.DoFullUpdate then
            gs:DoFullUpdate()
        end
    end)
end
