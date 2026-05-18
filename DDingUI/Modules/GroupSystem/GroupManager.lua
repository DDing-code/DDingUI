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

local function IsBuffSpellKey(spellName)
    return type(spellName) == "string" and spellName:match("^buff_") ~= nil
end

local function IsBuffGroup(groupName, groupSettings)
    if groupName == "Buffs" then return true end
    return groupSettings and groupSettings.groupCategory == "buff"
end

local function CanAssignCDMSpellToGroup(spellName, groupName, groupSettings)
    if not groupSettings then return false end
    if groupSettings.groupType ~= "dynamic" then return true end
    return IsBuffSpellKey(spellName) and IsBuffGroup(groupName, groupSettings)
end

local function GetUnassignedBuffSpells(gs, create)
    if not gs then return nil end
    if type(gs.unassignedBuffSpells) ~= "table" then
        if not create then return nil end
        gs.unassignedBuffSpells = {}
    end
    return gs.unassignedBuffSpells
end

local function BuildDynamicOrderToken(iconKey)
    if not iconKey or iconKey == "" then return nil end
    return "dyn:" .. tostring(iconKey)
end

local function IsCDMOrderToken(token)
    return type(token) == "string" and (token:match("^cdm:") or token:match("^cdm_id:"))
end

local function SafeNumber(value)
    if value == nil then return nil end
    local ok, result = pcall(function()
        if issecretvalue and issecretvalue(value) then return nil end
        return tonumber(value)
    end)
    if ok then return result end
    return nil
end

local function CollectCurrentDefaultCDMTokens(gs, groupName)
    local tokens, seen, entries = {}, {}, {}
    local cdm = DDingUI.CDMHookEngine or DDingUI.FrameController
    if not cdm then return tokens, seen end

    local map
    local ok = pcall(function()
        if cdm.GetIdIconMap then
            map = cdm:GetIdIconMap()
        elseif cdm.GetIconMap then
            map = cdm:GetIconMap()
        end
    end)
    if not ok or type(map) ~= "table" then return tokens, seen end

    local unassignedBuffs = GetUnassignedBuffSpells(gs, false)
    for cooldownID, icon in pairs(map) do
        local viewerName, defaultGroup, spellName
        pcall(function()
            if cdm.GetIconSource then viewerName = cdm:GetIconSource(cooldownID) end
        end)
        pcall(function()
            if cdm.GetDefaultGroupForViewer then defaultGroup = cdm:GetDefaultGroupForViewer(viewerName) end
        end)

        if defaultGroup == groupName then
            pcall(function()
                if cdm.GetSpellNameForID then spellName = cdm:GetSpellNameForID(cooldownID) end
            end)
            if not spellName and icon then
                pcall(function()
                    if cdm.GetSpellName then spellName = cdm:GetSpellName(icon) end
                end)
            end

            local token = BuildCDMOrderToken(spellName)
            local assigned = spellName and gs and gs.spellAssignments and gs.spellAssignments[spellName]
            local blocked = spellName and unassignedBuffs and unassignedBuffs[spellName]
            if token and not blocked and (not assigned or assigned == groupName) then
                entries[#entries + 1] = {
                    token = token,
                    order = SafeNumber(icon and icon.layoutIndex) or 99999,
                    cooldownID = SafeNumber(cooldownID) or 0,
                }
            end
        end
    end

    table.sort(entries, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        if a.cooldownID ~= b.cooldownID then return a.cooldownID < b.cooldownID end
        return tostring(a.token) < tostring(b.token)
    end)

    for _, entry in ipairs(entries) do
        local token = entry.token
        if token and not seen[token] then
            tokens[#tokens + 1] = token
            seen[token] = true
        end
    end

    return tokens, seen
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
    local orderedManualCDM = {}
    local orderedDynamic = {}
    local currentCDMSeen

    orderedCDM, currentCDMSeen = CollectCurrentDefaultCDMTokens(gs, groupName)
    for _, token in ipairs(orderedCDM) do
        valid[token] = true
    end

    if gs.spellAssignments then
        for spellName, assignedGroup in pairs(gs.spellAssignments) do
            if assignedGroup == groupName then
                local token = BuildCDMOrderToken(spellName)
                if token then
                    valid[token] = true
                    if not currentCDMSeen[token] then
                        orderedManualCDM[#orderedManualCDM + 1] = token
                    end
                end
            end
        end
    end
    table.sort(orderedManualCDM)

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
            if (valid[token] or IsCDMOrderToken(token)) and not seen[token] then
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
    for _, token in ipairs(orderedManualCDM) do
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

local function ReplaceGroupOrderToken(groupSettings, oldToken, newToken)
    local order = groupSettings and groupSettings.iconOrder
    if type(order) ~= "table" or not oldToken or not newToken then return false end

    local changed = false
    local primaryIndex
    for i, token in ipairs(order) do
        if token == oldToken then
            order[i] = newToken
            primaryIndex = i
            changed = true
            break
        end
    end

    if primaryIndex then
        for i = #order, 1, -1 do
            local token = order[i]
            if token == oldToken or (token == newToken and i ~= primaryIndex) then
                table.remove(order, i)
                changed = true
            end
        end
    end
    return changed
end

local function GetCopiedCDMBuffSpellName(iconData)
    if not iconData or (iconData.type ~= "spell" and iconData.type ~= "aura") then return nil end
    local settings = iconData.settings
    if not settings or settings.copiedFromCDM ~= true then return nil end

    if IsBuffSpellKey(settings.sourceSpellName) then
        return settings.sourceSpellName
    end

    local spellID = tonumber(iconData.id)
    if not spellID or spellID <= 0 then return nil end
    local ok, info = pcall(function()
        return C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    end)
    local spellName = ok and info and info.name
    if type(spellName) == "string" and spellName ~= "" and not (issecretvalue and issecretvalue(spellName)) then
        return "buff_" .. spellName
    end
    return nil
end

local function ConvertCopiedBuffDynamicIcons(gs)
    if DDingUI._convertingCopiedBuffIcons then return false end
    if not gs or not gs.groups then return false end

    local profile = DDingUI.db and DDingUI.db.profile
    local dynDB = profile and profile.dynamicIcons
    local iconDataDB = dynDB and dynDB.iconData
    local ci = DDingUI.CustomIcons
    if not iconDataDB or not ci or not ci.RemoveDynamicIcon then return false end

    local converted = {}
    for groupName, groupSettings in pairs(gs.groups) do
        if groupSettings and IsBuffGroup(groupName, groupSettings) then
            local sourceKey = groupSettings.sourceGroupKey
            local dynGroup = sourceKey and dynDB.groups and dynDB.groups[sourceKey]
            if dynGroup and dynGroup.icons then
                for _, iconKey in ipairs(dynGroup.icons) do
                    local spellName = GetCopiedCDMBuffSpellName(iconDataDB[iconKey])
                    if spellName then
                        converted[#converted + 1] = {
                            groupName = groupName,
                            groupSettings = groupSettings,
                            iconKey = iconKey,
                            spellName = spellName,
                        }
                    end
                end
            end
        end
    end
    if #converted == 0 then return false end

    if not gs.spellAssignments then gs.spellAssignments = {} end
    DDingUI._convertingCopiedBuffIcons = true

    for _, entry in ipairs(converted) do
        local newToken = BuildCDMOrderToken(entry.spellName)
        if newToken then
            if gs.spellAssignments[entry.spellName] ~= entry.groupName then
                RemoveTokenFromAllGroups(gs, newToken)
            end
            gs.spellAssignments[entry.spellName] = entry.groupName
            local unassignedBuffs = GetUnassignedBuffSpells(gs, false)
            if unassignedBuffs then
                unassignedBuffs[entry.spellName] = nil
            end
            AppendGroupIconOrderToken(gs, entry.groupName, newToken)
            ReplaceGroupOrderToken(entry.groupSettings, BuildDynamicOrderToken(entry.iconKey), newToken)
        end
    end

    for _, entry in ipairs(converted) do
        pcall(ci.RemoveDynamicIcon, ci, entry.iconKey)
    end

    DDingUI._convertingCopiedBuffIcons = nil
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
        iconMotion = true,
        iconMotionDuration = 0.18,
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
    if not CanAssignCDMSpellToGroup(spellName, groupName, group) then
        return false
    end
    if not gs.spellAssignments then gs.spellAssignments = {} end
    local token = BuildCDMOrderToken(spellName)
    local previousGroup = gs.spellAssignments[spellName]
    if previousGroup ~= groupName then
        RemoveTokenFromAllGroups(gs, token)
    end
    local unassignedBuffs = IsBuffSpellKey(spellName) and GetUnassignedBuffSpells(gs, false)
    if unassignedBuffs then
        unassignedBuffs[spellName] = nil
    end
    gs.spellAssignments[spellName] = groupName
    AppendGroupIconOrderToken(gs, groupName, token)
    SaveCurrentSpecNow()
    return true
end

function GroupManager:UnassignSpell(spellName, opts)
    local gs = GetGroupSystemSettings()
    if not gs then return false end
    if gs.spellAssignments then
        gs.spellAssignments[spellName] = nil
    end
    if opts and opts.toUnassignedBuffPool and IsBuffSpellKey(spellName) then
        local unassignedBuffs = GetUnassignedBuffSpells(gs, true)
        unassignedBuffs[spellName] = true
    end
    RemoveTokenFromAllGroups(gs, BuildCDMOrderToken(spellName))
    SaveCurrentSpecNow()
    return true
end

function GroupManager:MoveSpellToUnassigned(spellName)
    return self:UnassignSpell(spellName, { toUnassignedBuffPool = true })
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
    if not gs or not gs.groups then return false end

    local converted = ConvertCopiedBuffDynamicIcons(gs)
    if not gs.spellAssignments then return converted == true end
    local toRemove
    for spellName, groupName in pairs(gs.spellAssignments) do
        local group = gs.groups[groupName]
        if not CanAssignCDMSpellToGroup(spellName, groupName, group) then
            if not toRemove then toRemove = {} end
            toRemove[#toRemove + 1] = spellName
        end
    end

    if not toRemove then
        if converted and DDingUI.SpecProfiles and DDingUI.SpecProfiles.MarkDirty then
            DDingUI.SpecProfiles:MarkDirty()
        end
        return converted == true
    end
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

    -- CDM 원본은 일반 그룹으로 분류하되, 강화효과 CDM 스펠만 커스텀 buff 그룹에 재배치할 수 있다.
    local function resolveCDMGroup(groupName, spellKey)
        if not groupName then return nil end
        local g = gs.groups[groupName]
        if not CanAssignCDMSpellToGroup(spellKey, groupName, g) then return nil end
        return groupName
    end

    -- 1순위: 수동 할당 (spellName 기반)
    -- 일반 dynamic 그룹은 CustomIcons 전용으로 유지한다. buff 그룹만 CDM 원본 재배치를 허용한다.
    if spellName and gs.spellAssignments and gs.spellAssignments[spellName] then
        local assigned = resolveCDMGroup(gs.spellAssignments[spellName], spellName)
        if assigned and gs.groups[assigned] and gs.groups[assigned].enabled then
            return assigned
        end
    end

    local unassignedBuffs = IsBuffSpellKey(spellName) and GetUnassignedBuffSpells(gs, false)
    if unassignedBuffs and unassignedBuffs[spellName] then
        return nil
    end

    -- 2순위: 뷰어 소스 기반 자동 분류 (기본 그룹)
    local viewerName = CDMHookEngine:GetIconSource(cooldownID)
    if gs.autoClassify then
        local defaultGroup = CDMHookEngine:GetDefaultGroupForViewer(viewerName)
        if defaultGroup and gs.groups[defaultGroup] and gs.groups[defaultGroup].enabled then
            local result = resolveCDMGroup(defaultGroup, spellName)
            if result then return result end
        end
    end

    -- 3순위: autoFilter 매칭
    if viewerName then
        local filterGroup = self:FindGroupByViewerFilter(viewerName)
        local result = resolveCDMGroup(filterGroup, spellName)
        if result then return result end
    end

    -- 4순위: autoFilter = "ALL" 그룹
    local allGroup = self:FindGroupByFilter("ALL")
    local allResult = resolveCDMGroup(allGroup, spellName)
    if allResult then return allResult end

    -- 5순위: 첫 번째 활성 그룹
    return resolveCDMGroup(self:GetFirstEnabledGroup(), spellName)
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
