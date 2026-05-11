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

local function SaveCurrentSpecNow()
    if DDingUI.SpecProfiles and DDingUI.SpecProfiles.SaveCurrentSpec then
        DDingUI.SpecProfiles:SaveCurrentSpec()
    end
end

local function BuildCDMOrderToken(spellName)
    if not spellName or spellName == "" then return nil end
    return "cdm:" .. tostring(spellName)
end

local function BuildDynamicOrderToken(iconKey)
    if not iconKey or iconKey == "" then return nil end
    return "dyn:" .. tostring(iconKey)
end

local function RemoveTokenFromList(list, token)
    if type(list) ~= "table" or not token then return false end
    local changed = false
    for i = #list, 1, -1 do
        if list[i] == token then
            table.remove(list, i)
            changed = true
        end
    end
    return changed
end

local function HasToken(list, token)
    if type(list) ~= "table" or not token then return false end
    for _, existing in ipairs(list) do
        if existing == token then return true end
    end
    return false
end

local function RemoveTokenFromAllGroups(gs, token, exceptGroup)
    if not gs or not gs.groups or not token then return false end
    local changed = false
    for groupName, settings in pairs(gs.groups) do
        if groupName ~= exceptGroup and settings and RemoveTokenFromList(settings.iconOrder, token) then
            changed = true
        end
    end
    return changed
end

local function GetLinkedDynamicIcons(groupSettings)
    local sourceKey = groupSettings and groupSettings.sourceGroupKey
    if not sourceKey then return nil end
    local profile = DDingUI.db and DDingUI.db.profile
    local dynDB = profile and profile.dynamicIcons
    local sourceGroup = dynDB and dynDB.groups and dynDB.groups[sourceKey]
    return sourceGroup and sourceGroup.icons
end

local function NormalizeGroupIconOrder(gs, groupName)
    local groupSettings = gs and gs.groups and gs.groups[groupName]
    if not groupSettings then return nil end

    local valid = {}
    local orderedCDM = {}
    local orderedDynamic = {}

    if gs.spellAssignments then
        for spellName, assignedGroup in pairs(gs.spellAssignments) do
            if assignedGroup == groupName then
                local token = BuildCDMOrderToken(spellName)
                if token then
                    valid[token] = true
                    orderedCDM[#orderedCDM + 1] = token
                end
            end
        end
    end
    table.sort(orderedCDM)

    local dynamicIcons = GetLinkedDynamicIcons(groupSettings)
    if type(dynamicIcons) == "table" then
        for _, iconKey in ipairs(dynamicIcons) do
            local token = BuildDynamicOrderToken(iconKey)
            if token then
                valid[token] = true
                orderedDynamic[#orderedDynamic + 1] = token
            end
        end
    end

    local normalized = {}
    local seen = {}
    if type(groupSettings.iconOrder) == "table" then
        for _, token in ipairs(groupSettings.iconOrder) do
            if valid[token] and not seen[token] then
                normalized[#normalized + 1] = token
                seen[token] = true
            end
        end
    end

    for _, token in ipairs(orderedCDM) do
        if not seen[token] then
            normalized[#normalized + 1] = token
            seen[token] = true
        end
    end
    for _, token in ipairs(orderedDynamic) do
        if not seen[token] then
            normalized[#normalized + 1] = token
            seen[token] = true
        end
    end

    groupSettings.iconOrder = normalized
    return normalized
end

local function AppendGroupIconOrderToken(gs, groupName, token)
    local groupSettings = gs and gs.groups and gs.groups[groupName]
    if not groupSettings or not token then return false end
    NormalizeGroupIconOrder(gs, groupName)
    groupSettings.iconOrder = groupSettings.iconOrder or {}
    if HasToken(groupSettings.iconOrder, token) then return false end
    groupSettings.iconOrder[#groupSettings.iconOrder + 1] = token
    return true
end

local function NormalizeGroupOrders(gs)
    if not gs or not gs.groups then return nil end

    local list = {}
    for name, settings in pairs(gs.groups) do
        list[#list + 1] = {
            name = name,
            settings = settings,
            order = tonumber(settings and settings.order) or 999,
        }
    end

    table.sort(list, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return tostring(a.name) < tostring(b.name)
    end)

    for i, entry in ipairs(list) do
        if entry.settings then
            entry.settings.order = i
        end
    end

    return list
end

-- ============================================================
-- 그룹 CRUD (변경 없음)
-- ============================================================

function GroupManager:GetGroups()
    local gs = GetGroupSystemSettings()
    if not gs or not gs.groups then return {} end

    return NormalizeGroupOrders(gs) or {}
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

    SaveCurrentSpecNow()
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
    SaveCurrentSpecNow()
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

    SaveCurrentSpecNow()
    return true
end

function GroupManager:ReorderGroup(sourceName, targetName, insertAfter)
    local gs = GetGroupSystemSettings()
    if not gs or not gs.groups or not sourceName or not targetName then return false end
    if sourceName == targetName then return false end
    if not gs.groups[sourceName] or not gs.groups[targetName] then return false end

    local list = NormalizeGroupOrders(gs)
    if not list then return false end

    local sourceIndex, targetIndex
    for i, entry in ipairs(list) do
        if entry.name == sourceName then sourceIndex = i end
        if entry.name == targetName then targetIndex = i end
    end
    if not sourceIndex or not targetIndex or sourceIndex == targetIndex then return false end

    local moving = table.remove(list, sourceIndex)
    if sourceIndex < targetIndex then
        targetIndex = targetIndex - 1
    end

    local insertIndex = insertAfter and (targetIndex + 1) or targetIndex
    if insertIndex < 1 then insertIndex = 1 end
    if insertIndex > #list + 1 then insertIndex = #list + 1 end
    table.insert(list, insertIndex, moving)

    for i, entry in ipairs(list) do
        if entry.settings then
            entry.settings.order = i
        end
    end

    SaveCurrentSpecNow()
    return true
end

-- ============================================================
-- 스펠 수동 할당 (키: spellName)
-- [REFACTOR] spellID → spellName 기반으로 변경
-- ============================================================

function GroupManager:AssignSpell(spellName, groupName)
    local gs = GetGroupSystemSettings()
    if not gs then return false end
    local group = gs.groups and gs.groups[groupName]
    if not group or group.groupType == "dynamic" then
        return false
    end
    if not gs.spellAssignments then gs.spellAssignments = {} end
    local token = BuildCDMOrderToken(spellName)
    local previousGroup = gs.spellAssignments[spellName]
    if previousGroup ~= groupName then
        RemoveTokenFromAllGroups(gs, token)
    end
    gs.spellAssignments[spellName] = groupName
    AppendGroupIconOrderToken(gs, groupName, token)
    SaveCurrentSpecNow()
    return true
end

function GroupManager:UnassignSpell(spellName)
    local gs = GetGroupSystemSettings()
    if not gs or not gs.spellAssignments then return false end
    gs.spellAssignments[spellName] = nil
    RemoveTokenFromAllGroups(gs, BuildCDMOrderToken(spellName))
    SaveCurrentSpecNow()
    return true
end

function GroupManager:NormalizeGroupIconOrder(groupName)
    local gs = GetGroupSystemSettings()
    return NormalizeGroupIconOrder(gs, groupName)
end

function GroupManager:ReorderGroupIcon(groupName, sourceToken, targetToken, insertAfter, dropAction)
    local gs = GetGroupSystemSettings()
    if not gs or not groupName or not sourceToken or not targetToken then return false end
    if sourceToken == targetToken then return false end

    local order = NormalizeGroupIconOrder(gs, groupName)
    if type(order) ~= "table" then return false end

    local sourceIndex, targetIndex
    for i, token in ipairs(order) do
        if token == sourceToken then sourceIndex = i end
        if token == targetToken then targetIndex = i end
    end
    if not sourceIndex or not targetIndex or sourceIndex == targetIndex then return false end

    if dropAction == "swap" then
        order[sourceIndex], order[targetIndex] = order[targetIndex], order[sourceIndex]
        SaveCurrentSpecNow()
        return true
    end

    local moving = table.remove(order, sourceIndex)
    if sourceIndex < targetIndex then
        targetIndex = targetIndex - 1
    end

    local insertIndex = insertAfter and (targetIndex + 1) or targetIndex
    if insertIndex < 1 then insertIndex = 1 end
    if insertIndex > #order + 1 then insertIndex = #order + 1 end
    table.insert(order, insertIndex, moving)

    SaveCurrentSpecNow()
    return true
end

function GroupManager:ReorderAssignedSpell(groupName, spellName, targetSpellName, insertAfter)
    return self:ReorderGroupIcon(groupName, BuildCDMOrderToken(spellName), BuildCDMOrderToken(targetSpellName), insertAfter)
end

function GroupManager:PruneInvalidAssignments()
    local gs = GetGroupSystemSettings()
    if not gs or not gs.spellAssignments or not gs.groups then return false end

    local toRemove
    for spellName, groupName in pairs(gs.spellAssignments) do
        local group = gs.groups[groupName]
        if not group or group.groupType == "dynamic" then
            if not toRemove then toRemove = {} end
            toRemove[#toRemove + 1] = spellName
        end
    end

    if not toRemove then return false end
    for _, spellName in ipairs(toRemove) do
        gs.spellAssignments[spellName] = nil
        RemoveTokenFromAllGroups(gs, BuildCDMOrderToken(spellName))
    end

    if DDingUI.SpecProfiles and DDingUI.SpecProfiles.MarkDirty then
        DDingUI.SpecProfiles:MarkDirty()
    end
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

    local spellName = CDMHookEngine:GetSpellNameForID(cooldownID)

    -- [Fix C] 캐시 미스 시 아이콘에서 직접 추출 (전투 중 secret value 해제 즉시 반영)
    if not spellName then
        local icon = CDMHookEngine:GetIconFrame(cooldownID)
        if icon and CDMHookEngine.GetSpellName then
            spellName = CDMHookEngine:GetSpellName(icon)
        end
    end

    local cleanSpellName
    if spellName then
        cleanSpellName = spellName:match("^buff_(.+)") or spellName
    end

    -- [REMOVED] 0순위 다이나믹 그룹 하이재킹 제거
    -- DynamicIconBridge가 CustomIcons 프레임을 직접 제공하므로
    -- CDM 아이콘을 커스텀 그룹으로 분류하면 중복 발생 (CDM 프레임 + CustomIcons 프레임)

    -- [FIX] dynamic 그룹 필터 — CDM 아이콘은 dynamic 그룹에 절대 들어가면 안 됨
    local function notDynamic(groupName)
        if not groupName then return nil end
        local g = gs.groups[groupName]
        if g and g.groupType == "dynamic" then return nil end
        return groupName
    end

    -- 1순위: 수동 할당 (spellName 기반)
    -- dynamic 그룹은 CustomIcons 복사본으로만 표시한다. CDM 원본을 dynamic으로 분류하면
    -- 기존 CDM 그룹에서 빠지고 CustomIcons 복사본과 중복 렌더링된다.
    if spellName and gs.spellAssignments and gs.spellAssignments[spellName] then
        local assigned = notDynamic(gs.spellAssignments[spellName])
        if assigned and gs.groups[assigned] and gs.groups[assigned].enabled then
            return assigned
        end
    end

    -- 2순위: 뷰어 소스 기반 자동 분류 (기본 그룹)
    local viewerName = CDMHookEngine:GetIconSource(cooldownID)
    if gs.autoClassify then
        local defaultGroup = CDMHookEngine:GetDefaultGroupForViewer(viewerName)
        if defaultGroup and gs.groups[defaultGroup] and gs.groups[defaultGroup].enabled then
            local result = notDynamic(defaultGroup)
            if result then return result end
        end
    end

    -- 3순위: autoFilter 매칭
    if viewerName then
        local filterGroup = self:FindGroupByViewerFilter(viewerName)
        local result = notDynamic(filterGroup)
        if result then return result end
    end

    -- 4순위: autoFilter = "ALL" 그룹
    local allGroup = self:FindGroupByFilter("ALL")
    local allResult = notDynamic(allGroup)
    if allResult then return allResult end

    -- 5순위: 첫 번째 활성 그룹
    return notDynamic(self:GetFirstEnabledGroup())
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
    self:PruneInvalidAssignments()

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
