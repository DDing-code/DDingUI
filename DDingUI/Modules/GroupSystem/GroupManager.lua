-- [GROUP SYSTEM] GroupManager: 그룹 관리 + CDM 뷰어 기반 분류 엔진
-- [REFACTOR] AuraEngine 기반 → CDMHookEngine 뷰어 기반으로 전환
local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
if not DDingUI then return end

local GroupManager = {}
DDingUI.GroupManager = GroupManager

-- Locals
local pairs = pairs
local type = type
local wipe = wipe

-- ============================================================
-- 프로필 접근 헬퍼
-- ============================================================

local function GetGroupSystemSettings()
    local profile = DDingUI.db and DDingUI.db.profile
    return profile and profile.groupSystem
end

local function GetGroupSettings(groupName)
    local gs = GetGroupSystemSettings()
    return gs and gs.groups and gs.groups[groupName]
end

local function GetSpellAssignments()
    local gs = GetGroupSystemSettings()
    return gs and gs.spellAssignments or {}
end

-- ============================================================
-- 그룹 CRUD (변경 없음)
-- ============================================================

function GroupManager:GetGroups()
    local gs = GetGroupSystemSettings()
    if not gs or not gs.groups then return {} end

    -- order 순으로 정렬된 배열 반환
    local sorted = {}
    for name, settings in pairs(gs.groups) do
        sorted[#sorted + 1] = {
            name = name,
            settings = settings,
            order = settings.order or 999,
        }
    end
    table.sort(sorted, function(a, b) return a.order < b.order end)
    return sorted
end

function GroupManager:GetGroupByName(groupName)
    return GetGroupSettings(groupName)
end

function GroupManager:CreateGroup(name, settings)
    local gs = GetGroupSystemSettings()
    if not gs then return false end
    if gs.groups[name] then return false end -- 이미 존재

    -- 최대 order 찾기
    local maxOrder = 0
    for _, g in pairs(gs.groups) do
        if g.order and g.order > maxOrder then
            maxOrder = g.order
        end
    end

    -- 기본 그룹 설정 복사 + 오버라이드
    local defaults = {
        order = maxOrder + 1,
        groupType = "dynamic",
        groupCategory = "skill", -- "skill" | "buff" (사용자 변경 가능)
        autoFilter = "ALL",
        enabled = true,
        iconSize = 32,
        aspectRatioCrop = 1.0,
        spacing = 2,
        zoom = 0.08,
        borderSize = 1,
        borderColor = { 0, 0, 0, 1 },
        direction = "RIGHT",
        growDirection = "DOWN",
        rowLimit = 8,
        swipeColor = { 0, 0, 0, 0.8 },
        swipeReverse = true,
        anchorPoint = "CENTER",
        offsetX = 0,
        offsetY = 0,
    }

    if settings then
        for k, v in pairs(settings) do
            defaults[k] = v
        end
    end

    gs.groups[name] = defaults
    -- 삭제 기록에서 제거 (사용자가 다시 만든 것)
    if gs.deletedGroups then gs.deletedGroups[name] = nil end

    -- [FIX] 생성 즉시 CustomIcons 그룹 연결 (sourceGroupKey가 없으면 UpdateDynamicGroup이 hide 처리)
    -- Ayije CDM처럼: 그룹 생성 시점에 모든 필요한 데이터를 즉시 준비
    local ci = DDingUI.CustomIcons
    if ci and ci.CreateDynamicGroup and not defaults.sourceGroupKey then
        local sourceKey = ci:CreateDynamicGroup(name)
        if sourceKey then
            defaults.sourceGroupKey = sourceKey
        end
    end

    return true
end

function GroupManager:DeleteGroup(name)
    local gs = GetGroupSystemSettings()
    if not gs or not gs.groups[name] then return false end

    -- 이 그룹에 할당된 스펠도 정리
    if gs.spellAssignments then
        for spellKey, assignedGroup in pairs(gs.spellAssignments) do
            if assignedGroup == name then
                gs.spellAssignments[spellKey] = nil
            end
        end
    end

    -- 삭제 기록 (SyncDynamicGroups가 재생성하지 않도록)
    if not gs.deletedGroups then gs.deletedGroups = {} end
    gs.deletedGroups[name] = true

    gs.groups[name] = nil
    return true
end

function GroupManager:RenameGroup(oldName, newName)
    local gs = GetGroupSystemSettings()
    if not gs or not gs.groups[oldName] or gs.groups[newName] then return false end

    gs.groups[newName] = gs.groups[oldName]
    gs.groups[oldName] = nil

    -- 스펠 할당도 업데이트
    if gs.spellAssignments then
        for spellKey, assignedGroup in pairs(gs.spellAssignments) do
            if assignedGroup == oldName then
                gs.spellAssignments[spellKey] = newName
            end
        end
    end

    return true
end

-- ============================================================
-- 스펠 수동 할당 (키: spellName)
-- [REFACTOR] spellID → spellName 기반으로 변경
-- ============================================================

function GroupManager:AssignSpell(spellName, groupName)
    local gs = GetGroupSystemSettings()
    if not gs then return false end
    if not gs.spellAssignments then gs.spellAssignments = {} end
    gs.spellAssignments[spellName] = groupName
    return true
end

function GroupManager:UnassignSpell(spellName)
    local gs = GetGroupSystemSettings()
    if not gs or not gs.spellAssignments then return false end
    gs.spellAssignments[spellName] = nil
    return true
end

function GroupManager:GetSpellAssignment(spellName)
    local assignments = GetSpellAssignments()
    return assignments[spellName]
end

-- ============================================================
-- CDM 뷰어 기반 분류 엔진
-- [REFACTOR] ClassifyAura(auraData) → ClassifyIcon(cooldownID)
-- ============================================================

function GroupManager:ClassifyIcon(cooldownID)
    local CDMHookEngine = DDingUI.CDMHookEngine
    if not CDMHookEngine then return nil end

    local gs = GetGroupSystemSettings()
    if not gs then return nil end

    -- 1순위: 수동 할당 (spellName 기반)
    local spellName = CDMHookEngine:GetSpellNameForID(cooldownID)
    if spellName and gs.spellAssignments and gs.spellAssignments[spellName] then
        local assigned = gs.spellAssignments[spellName]
        -- 할당된 그룹이 실제로 존재하고 활성화되어 있는지 확인
        if gs.groups[assigned] and gs.groups[assigned].enabled then
            return assigned
        end
    end

    -- 2순위: 뷰어 소스 기반 자동 분류 (기본 그룹)
    local viewerName = CDMHookEngine:GetIconSource(cooldownID)
    if gs.autoClassify then
        local defaultGroup = CDMHookEngine:GetDefaultGroupForViewer(viewerName)
        if defaultGroup and gs.groups[defaultGroup] and gs.groups[defaultGroup].enabled then
            return defaultGroup
        end
    end

    -- 3순위: autoFilter 매칭
    if viewerName then
        local filterGroup = self:FindGroupByViewerFilter(viewerName)
        if filterGroup then return filterGroup end
    end

    -- 4순위: autoFilter = "ALL" 그룹
    local allGroup = self:FindGroupByFilter("ALL")
    if allGroup then return allGroup end

    -- 5순위: 첫 번째 활성 그룹
    return self:GetFirstEnabledGroup()
end

-- 뷰어 이름 → autoFilter 매칭
function GroupManager:FindGroupByViewerFilter(viewerName)
    local filterMap = {
        ["EssentialCooldownViewer"] = "COOLDOWN",
        ["UtilityCooldownViewer"] = "UTILITY",
        ["BuffIconCooldownViewer"] = "HELPFUL",
    }
    local filterType = filterMap[viewerName]
    if filterType then
        return self:FindGroupByFilter(filterType)
    end
    return nil
end

-- autoFilter로 그룹 찾기 (변경 없음)
function GroupManager:FindGroupByFilter(filterType)
    local gs = GetGroupSystemSettings()
    if not gs or not gs.groups then return nil end

    local best = nil
    local bestOrder = 9999

    for name, settings in pairs(gs.groups) do
        if settings.enabled and settings.autoFilter == filterType then
            local order = settings.order or 999
            if order < bestOrder then
                best = name
                bestOrder = order
            end
        end
    end

    return best
end

-- 첫 번째 활성 그룹 (변경 없음)
function GroupManager:GetFirstEnabledGroup()
    local gs = GetGroupSystemSettings()
    if not gs or not gs.groups then return nil end

    local best = nil
    local bestOrder = 9999

    for name, settings in pairs(gs.groups) do
        if settings.enabled then
            local order = settings.order or 999
            if order < bestOrder then
                best = name
                bestOrder = order
            end
        end
    end

    return best
end

-- ============================================================
-- CDMHookEngine 맵 기반 전체 분류
-- [REFACTOR] allData(auraData 배열) → idIconMap(cooldownID→icon) 순회
-- ============================================================

function GroupManager:ClassifyAll()
    local CDMHookEngine = DDingUI.CDMHookEngine
    if not CDMHookEngine then return {} end

    local idIconMap = CDMHookEngine:GetIconMap()
    local result = {} -- [groupName] = { {cooldownID=, icon=, spellName=}... }

    -- 빈 그룹 초기화
    local gs = GetGroupSystemSettings()
    if gs and gs.groups then
        for name, settings in pairs(gs.groups) do
            if settings.enabled then
                result[name] = {}
            end
        end
    end

    -- 각 cooldownID를 그룹에 배치
    for cooldownID, icon in pairs(idIconMap) do
        local groupName = self:ClassifyIcon(cooldownID)
        if groupName and result[groupName] then
            result[groupName][#result[groupName] + 1] = {
                cooldownID = cooldownID,
                icon = icon,
                spellName = CDMHookEngine:GetSpellNameForID(cooldownID),
            }
        end
    end

    -- [REPARENT] CDM 뷰어의 원래 아이콘 순서 유지 (layoutIndex 기반 정렬)
    -- layoutIndex가 secret value일 수 있으므로 pcall로 안전하게 접근
    local function SafeLayoutIndex(icon)
        if not icon then return 0 end
        local ok, val = pcall(function()
            local li = icon.layoutIndex
            if li == nil then return nil end
            if issecretvalue and issecretvalue(li) then return nil end
            return li
        end)
        if ok and val then return val end
        -- fallback: cooldownID 순서
        local okID, cdID = pcall(function() return icon.cooldownID end)
        if okID and cdID and type(cdID) == "number" then return cdID end
        return 0
    end

    for groupName, iconList in pairs(result) do
        table.sort(iconList, function(a, b)
            return SafeLayoutIndex(a.icon) < SafeLayoutIndex(b.icon)
        end)
    end

    return result
end
