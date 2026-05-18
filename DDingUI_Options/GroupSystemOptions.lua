-- [GROUP SYSTEM] Config UI for Group System
local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
local L = LibStub("AceLocale-3.0"):GetLocale("DDingUI")

-- [CONFIRM] 그룹 삭제 확인 팝업
StaticPopupDialogs["DDINGUI_DELETE_GROUP"] = {
    text = L["Are you sure you want to delete '%s'?"] or "정말 '%s' 그룹을 삭제하시겠습니까?",
    button1 = YES,
    button2 = NO,
    OnAccept = function(self)
        if self.data and self.data.onAccept then
            self.data.onAccept()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- [12.0.1] 그룹 이름 변경 팝업
StaticPopupDialogs["DDINGUI_RENAME_GROUP"] = {
    text = L["Enter new group name:"] or "새 그룹 이름을 입력하세요:",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = true,
    editBoxWidth = 200,
    OnShow = function(self)
        local eb = self.editBox or self.EditBox
        if eb and self.data and self.data.oldName then
            eb:SetText(self.data.oldName)
            eb:HighlightText()
            eb:SetFocus()
        end
    end,
    OnAccept = function(self)
        local eb = self.editBox or self.EditBox
        if eb and self.data and self.data.onAccept then
            local newName = eb:GetText()
            if newName and newName ~= "" then
                self.data.onAccept(newName)
            end
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        local data = parent.data
        if data and data.onAccept then
            local newName = self:GetText()
            if newName and newName ~= "" then
                data.onAccept(newName)
            end
        end
        parent:Hide()
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local DIRECTION_VALUES = {
    ["RIGHT"]               = L["Right"] or "오른쪽",
    ["LEFT"]                = L["Left"] or "왼쪽",
    ["UP"]                  = L["Up"] or "위",
    ["DOWN"]                = L["Down"] or "아래",
    ["CENTERED_HORIZONTAL"] = L["Centered Horizontal"] or "가운데 정렬(가로)",
}

local FILTER_VALUES = {
    ["HELPFUL"]  = L["Buffs"] or "버프",
    ["HARMFUL"]  = L["Debuffs"] or "디버프",
    ["COOLDOWN"] = L["Essential Cooldowns"] or "핵심 능력",
    ["UTILITY"]  = L["Utility Cooldowns"] or "보조 능력",
    ["ALL"]      = L["All"] or "전체",
}

local CDM_ENTRY_CACHE_TTL = 0.5
local GROUP_QUICK_ASSIGN_ENABLED = false
local GROUP_SPELL_INPUT_ENABLED = false
local cdmEntryCache
local cdmEntryCacheTime = 0

local function InvalidateCDMIconEntryCache()
    cdmEntryCache = nil
    cdmEntryCacheTime = 0
end
DDingUI.InvalidateGroupCDMIconEntryCache = InvalidateCDMIconEntryCache

local ANCHOR_VALUES = {
    ["CENTER"]      = "CENTER",
    ["TOP"]         = "TOP",
    ["BOTTOM"]      = "BOTTOM",
    ["LEFT"]        = "LEFT",
    ["RIGHT"]       = "RIGHT",
    ["TOPLEFT"]     = "TOPLEFT",
    ["TOPRIGHT"]    = "TOPRIGHT",
    ["BOTTOMLEFT"]  = "BOTTOMLEFT",
    ["BOTTOMRIGHT"] = "BOTTOMRIGHT",
}

local tinsert = tinsert or table.insert
local FLAT = "Interface\\Buttons\\WHITE8x8"

-- 헬퍼: groupSystem 설정 접근
local function GetGS()
    if not DDingUI.db or not DDingUI.db.profile then return nil end
    return DDingUI.db.profile.groupSystem
end

local function RefreshGroupSystem()
    InvalidateCDMIconEntryCache()

    -- [FIX] 전투 중 named frame의 ClearAllPoints() 호출 → ADDON_ACTION_BLOCKED 방지
    -- 전투 종료 후 Refresh 예약
    if InCombatLockdown() then
        if not DDingUI._pendingGroupRefresh then
            DDingUI._pendingGroupRefresh = true
            local f = DDingUI._groupRefreshFrame
            if not f then
                f = CreateFrame("Frame")
                DDingUI._groupRefreshFrame = f
            end
            f:RegisterEvent("PLAYER_REGEN_ENABLED")
            f:SetScript("OnEvent", function(self)
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                DDingUI._pendingGroupRefresh = false
                RefreshGroupSystem()
            end)
        end
        return
    end
    if DDingUI.GroupSystem and DDingUI.GroupSystem.Refresh then
        DDingUI.GroupSystem:Refresh()
    end
    if DDingUI.AssistHighlight and DDingUI.AssistHighlight.OnSettingChanged then
        DDingUI.AssistHighlight:OnSettingChanged()
    elseif DDingUI.AssistHighlight and DDingUI.AssistHighlight.RefreshAll then
        DDingUI.AssistHighlight:RefreshAll()
    end
    -- [FIX] 설정 변경을 SpecProfiles 스냅샷에 반영
    -- 누락 시 캐릭 전환/리로드에서 LoadSpec이 스냅샷(구 값)으로 덮어씀
    if DDingUI.SpecProfiles and DDingUI.SpecProfiles.MarkDirty then
        DDingUI.SpecProfiles:MarkDirty()
    end
end

-- [FIX] 수동 생성 그룹에 아이템/장신구 추가 시 CustomIcons 그룹과 자동 연결
-- sourceGroupKey가 없는 dynamic 그룹에 CustomIcons 그룹을 자동 생성하여 연결
local CORE_CDM_GROUPS = {
    Cooldowns = true,
    Buffs = true,
    Utility = true,
}

local function MarkSpecProfileDirty()
    if DDingUI.SpecProfiles and DDingUI.SpecProfiles.MarkDirty then
        DDingUI.SpecProfiles:MarkDirty()
    end
end

local function EnsureSourceGroup(groupName)
    local gs = GetGS()
    if not gs or not gs.groups or not gs.groups[groupName] then return nil end
    local grp = gs.groups[groupName]
    local isCoreCDMGroup = CORE_CDM_GROUPS[groupName] == true
    if isCoreCDMGroup and grp.groupType ~= "cdm" then
        grp.groupType = "cdm"
    end
    local isCDMGroup = isCoreCDMGroup or grp.groupType ~= "dynamic"
    -- 이미 sourceGroupKey가 있으면 그대로 반환
    if grp.sourceGroupKey then
        local dynDB = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.dynamicIcons
        local sourceGroup = dynDB and dynDB.groups and dynDB.groups[grp.sourceGroupKey]
        if sourceGroup then
            if isCDMGroup then
                sourceGroup.linkedCDMGroup = groupName
                sourceGroup.enabled = grp.enabled ~= false
            end
            return grp.sourceGroupKey
        end
        grp.sourceGroupKey = nil
    end

    local customIcons = DDingUI.CustomIcons
    if isCDMGroup and customIcons and customIcons.GetOrCreateSourceGroupForCDMGroup then
        local sourceKey = customIcons:GetOrCreateSourceGroupForCDMGroup(groupName, grp.name or groupName)
        if sourceKey then
            MarkSpecProfileDirty()
            return sourceKey
        end
    end

    -- CustomIcons 그룹 자동 생성
    local ci = DDingUI.CustomIcons
    if not ci or not ci.CreateDynamicGroup then return nil end
    local sourceKey = ci:CreateDynamicGroup(grp.name or groupName)
    if sourceKey then
        grp.sourceGroupKey = sourceKey
        local dynDB = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.dynamicIcons
        local sourceGroup = dynDB and dynDB.groups and dynDB.groups[sourceKey]
        if sourceGroup then
            sourceGroup.enabled = grp.enabled ~= false
            if isCDMGroup then
                sourceGroup.linkedCDMGroup = groupName
            end
        end
        -- [FIX] grp.groupType = "dynamic" 강제 변경 제거 (기본그룹 CDM 억제 방지)
        MarkSpecProfileDirty()
    end
    return sourceKey
end

local function GetUsableSpellAssignment(gs, spellName)
    if not gs or not spellName or not gs.spellAssignments then return nil end
    local assigned = gs.spellAssignments[spellName]
    if not assigned then return nil end

    local assignedGroup = gs.groups and gs.groups[assigned]
    local isBuffSpell = type(spellName) == "string" and spellName:match("^buff_") ~= nil
    local isDynamicBuffGroup = assignedGroup
        and assignedGroup.groupType == "dynamic"
        and isBuffSpell
        and (assigned == "Buffs" or assignedGroup.groupCategory == "buff")
    if not assignedGroup or (assignedGroup.groupType == "dynamic" and not isDynamicBuffGroup) then
        gs.spellAssignments[spellName] = nil
        MarkSpecProfileDirty()
        return nil
    end
    if assignedGroup.enabled == false then
        return nil
    end

    return assigned
end

-- [12.0.1] 레이아웃만 갱신 (아이콘 크기/간격/방향 변경 시)
-- _forceFullSetup 없이 DoFullUpdate → LayoutGroup이 SetIconSize로 크기 갱신
-- 디바운스 0.03초: 슬라이더 드래그 시 빈번한 호출 방지
local layoutRefreshTimer = nil
local function RefreshGroupLayout()
    if layoutRefreshTimer then layoutRefreshTimer:Cancel() end
    layoutRefreshTimer = C_Timer.NewTimer(0.03, function()
        layoutRefreshTimer = nil
        if DDingUI.GroupSystem and DDingUI.GroupSystem.RefreshLayout then
            DDingUI.GroupSystem:RefreshLayout()
        end
    end)
    -- [FIX] 레이아웃 변경도 SpecProfiles 스냅샷에 반영
    if DDingUI.SpecProfiles and DDingUI.SpecProfiles.MarkDirty then
        DDingUI.SpecProfiles:MarkDirty()
    end
end

-- [FIX] 동적 아이콘 변경 시 갱신 (메뉴 닫힘 없이)
-- 1. RefreshLayout: 게임 아이콘 레이아웃 즉시 갱신 (겹침 방지)
-- 2. SoftRefresh: 그룹 설정 페이지는 서브탭이 없어서 FullRefresh → SetContent
--    (전체 재빌드 = 창 닫힘). SoftRefresh는 콘텐츠만 재렌더링 (창 유지)
local function SoftRefreshGroupSystemOptions(delay)
    local function refreshGUI()
        local configFrame = _G["DDingUI_ConfigFrame"]
        if not configFrame or not configFrame:IsShown() then return end
        -- 옵션 테이블 재생성 (RefreshConfigGUI의 soft 경로와 동일)
        local currentTab = configFrame.currentTab or ""
        if currentTab:match("^groupSystem") and configFrame.configOptions then
            local createGSOpts = DDingUI._CreateGroupSystemOptions
            if createGSOpts then
                configFrame.configOptions.args.groupSystem = createGSOpts(1)
                DDingUI.configOptions = configFrame.configOptions
                if configFrame._optionLookup and configFrame._optionLookup[currentTab] then
                    local path = configFrame._optionLookup[currentTab].path
                    if path then
                        local opt = configFrame.configOptions
                        for _, key in ipairs(path) do
                            opt = opt and opt.args and opt.args[key]
                        end
                        if opt then
                            configFrame._optionLookup[currentTab].option = opt
                        end
                    end
                end
            end
        end
        -- SoftRefresh: 서브탭 없어도 안전 (FullRefresh는 서브탭 없으면 SetContent → 창 닫힘)
        if configFrame.SoftRefresh then
            configFrame:SoftRefresh()
        end
    end

    C_Timer.After(delay or 0, refreshGUI)
end

local function SoftRefreshDynamicIcons()
    InvalidateCDMIconEntryCache()

    -- 게임 레이아웃 갱신
    if DDingUI.GroupSystem and DDingUI.GroupSystem.RefreshLayout then
        DDingUI.GroupSystem:RefreshLayout()
    end
    -- GUI 목록 갱신 (지연, SoftRefresh로 메뉴 닫히지 않음)
    SoftRefreshGroupSystemOptions(0.1)
end

-- [12.0.1] 새 그룹 이름 임시 저장 (입력과 생성 분리 — 포커스 잃을 때 리프레시 방지)
local pendingGroupName = nil
local pendingItemID = nil

-- ============================================================
-- CDM 아이콘 할당 다이얼로그
-- ============================================================

local ICON_GRID_SIZE = 36
local ICON_GRID_SPACING = 4
local ICONS_PER_ROW = 8
local MAX_GRID_ICONS = 32

-- [REFACTOR] 팝업 다이얼로그 제거 → 인라인 그리드로 전환

-- [FIX] 전방 선언: GetGroupCategory는 line ~980에서 구현되지만 BuildGroupAssignGridUI에서 먼저 사용
local GetGroupCategory

-- [FIX] 그룹 이름 → 소속 CDM 뷰어 매핑 (필터링용)
local GROUP_VIEWER_MAP = {
    ["Cooldowns"] = "EssentialCooldownViewer",
    ["Buffs"]     = "BuffIconCooldownViewer",
    ["Utility"]   = "UtilityCooldownViewer",
}

-- [DYNAMIC] CDM 그룹 이름 → 한국어 표시명 매핑
local GROUP_DISPLAY_NAMES = {
    ["Cooldowns"] = L["Essential Cooldowns"] or "핵심 능력",
    ["Buffs"]     = L["Buffs Group"] or "강화 효과",
    ["Utility"]   = L["Utility Cooldowns"] or "보조 능력",
}

local function IsBuffGroup(groupName, groupSettings)
    if groupName == "Buffs" then return true end
    if groupSettings and groupSettings.groupCategory == "buff" then return true end
    return GROUP_VIEWER_MAP[groupName] == "BuffIconCooldownViewer"
end

local function IsBuffSpell(spellName, entry)
    if type(spellName) == "string" and spellName:match("^buff_") then return true end
    return entry and entry.viewerName == "BuffIconCooldownViewer"
end

local function GetUnassignedBuffSpells(gs, create)
    if not gs then return nil end
    if type(gs.unassignedBuffSpells) ~= "table" then
        if not create then return nil end
        gs.unassignedBuffSpells = {}
    end
    return gs.unassignedBuffSpells
end

local function IsBuffSpellUnassigned(gs, spellName)
    local unassigned = GetUnassignedBuffSpells(gs, false)
    return spellName and unassigned and unassigned[spellName] == true
end

local function FindBuffDynamicSpellOwner(gs, spellID, exceptGroup)
    spellID = tonumber(spellID)
    if not gs or not spellID or spellID <= 0 then return nil end

    local dynDB = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.dynamicIcons
    local iconDataDB = dynDB and dynDB.iconData
    if not iconDataDB then return nil end

    for groupName, groupSettings in pairs(gs.groups or {}) do
        if groupName ~= exceptGroup and groupSettings and IsBuffGroup(groupName, groupSettings) then
            local sourceKey = groupSettings.sourceGroupKey
            local dynGroup = sourceKey and dynDB.groups and dynDB.groups[sourceKey]
            if dynGroup and dynGroup.icons then
                for _, iconKey in ipairs(dynGroup.icons) do
                    local iconData = iconDataDB[iconKey]
                    if iconData and (iconData.type == "spell" or iconData.type == "aura") then
                        local existingID = tonumber(iconData.id)
                        if existingID and existingID == spellID then
                            return groupName, iconKey
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function ClearBuffSpellUnassigned(spellName)
    local gs = GetGS()
    local unassigned = GetUnassignedBuffSpells(gs, false)
    if unassigned and spellName then
        unassigned[spellName] = nil
    end
end

local function MoveBuffSpellToUnassigned(spellName)
    if not spellName or not IsBuffSpell(spellName) then return false end
    local GroupMgr = DDingUI.GroupManager
    if GroupMgr and GroupMgr.MoveSpellToUnassigned then
        return GroupMgr:MoveSpellToUnassigned(spellName)
    end

    local gs = GetGS()
    if not gs then return false end
    local unassigned = GetUnassignedBuffSpells(gs, true)
    unassigned[spellName] = true
    if gs.spellAssignments then
        gs.spellAssignments[spellName] = nil
    end
    MarkSpecProfileDirty()
    return true
end

local function RemoveBuffDynamicSpellCopies(spellID, exceptGroup)
    spellID = tonumber(spellID)
    if not spellID or spellID <= 0 then return false end

    local gs = GetGS()
    local dynDB = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.dynamicIcons
    local iconDataDB = dynDB and dynDB.iconData
    local ci = DDingUI.CustomIcons
    if not gs or not iconDataDB or not ci or not ci.RemoveDynamicIcon then return false end

    local removed = false
    for groupName, groupSettings in pairs(gs.groups or {}) do
        if groupName ~= exceptGroup and groupSettings and IsBuffGroup(groupName, groupSettings) then
            local sourceKey = groupSettings.sourceGroupKey
            local dynGroup = sourceKey and dynDB.groups and dynDB.groups[sourceKey]
            if dynGroup and dynGroup.icons then
                local toRemove = {}
                for _, iconKey in ipairs(dynGroup.icons) do
                    local iconData = iconDataDB[iconKey]
                    if iconData and (iconData.type == "spell" or iconData.type == "aura") then
                        local existingID = tonumber(iconData.id)
                        if existingID and existingID == spellID then
                            toRemove[#toRemove + 1] = iconKey
                        end
                    end
                end
                for _, iconKey in ipairs(toRemove) do
                    ci:RemoveDynamicIcon(iconKey)
                    removed = true
                end
            end
        end
    end
    return removed
end

local function GetCopiedCDMBuffSpellName(iconData)
    if not iconData or (iconData.type ~= "spell" and iconData.type ~= "aura") then return nil end
    local settings = iconData.settings
    if not settings or settings.copiedFromCDM ~= true then return nil end

    if type(settings.sourceSpellName) == "string" and settings.sourceSpellName:match("^buff_") then
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
    else
        local seenNew = false
        for i = #order, 1, -1 do
            local token = order[i]
            if token == oldToken then
                table.remove(order, i)
                changed = true
            elseif token == newToken then
                if not seenNew then
                    seenNew = true
                else
                    table.remove(order, i)
                    changed = true
                end
            end
        end
    end

    return changed
end

local function ConvertCopiedBuffDynamicIconsToAssignments(groupName, groupSettings)
    if DDingUI._convertingCopiedBuffIcons then return false end
    if not groupName or not groupSettings or not IsBuffGroup(groupName, groupSettings) then return false end

    local sourceKey = groupSettings.sourceGroupKey
    local dynDB = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.dynamicIcons
    local dynGroup = sourceKey and dynDB and dynDB.groups and dynDB.groups[sourceKey]
    local iconDataDB = dynDB and dynDB.iconData
    local ci = DDingUI.CustomIcons
    local GroupMgr = DDingUI.GroupManager
    if not dynGroup or not dynGroup.icons or not iconDataDB or not ci or not ci.RemoveDynamicIcon or not GroupMgr or not GroupMgr.AssignSpell then
        return false
    end

    local toRemove = {}
    for _, iconKey in ipairs(dynGroup.icons) do
        local iconData = iconDataDB[iconKey]
        local spellName = GetCopiedCDMBuffSpellName(iconData)
        if spellName then
            toRemove[#toRemove + 1] = { iconKey = iconKey, spellName = spellName }
        end
    end
    if #toRemove == 0 then return false end

    DDingUI._convertingCopiedBuffIcons = true
    local changed = false
    for _, entry in ipairs(toRemove) do
        if GroupMgr:AssignSpell(entry.spellName, groupName) then
            ReplaceGroupOrderToken(groupSettings, "dyn:" .. tostring(entry.iconKey), "cdm:" .. tostring(entry.spellName))
            changed = true
        end
    end
    for _, entry in ipairs(toRemove) do
        pcall(ci.RemoveDynamicIcon, ci, entry.iconKey)
        changed = true
    end
    DDingUI._convertingCopiedBuffIcons = nil

    if changed then
        MarkSpecProfileDirty()
        InvalidateCDMIconEntryCache()
    end
    return changed
end

local function SafeCDMLayoutIndex(icon, fallback)
    if not icon then return fallback or 0 end

    local ok, value = pcall(function()
        local layoutIndex = icon.layoutIndex
        if layoutIndex == nil then return nil end
        if issecretvalue and issecretvalue(layoutIndex) then return nil end
        return layoutIndex
    end)
    if ok and type(value) == "number" then return value end

    local okID, cooldownID = pcall(function()
        local cdID = icon.cooldownID
        if issecretvalue and issecretvalue(cdID) then return nil end
        return cdID
    end)
    if okID and type(cooldownID) == "number" then return cooldownID end

    return fallback or 0
end

-- CDMHookEngine에서 전체 뷰어 아이콘 목록 수집
-- [FIX] CDMScanner는 BuffIcon/BuffBar만 스캔 → Essential/Utility 누락
-- CDMHookEngine은 3개 뷰어 모두 스캔하므로 그룹 할당 그리드에 적합
local function GetCDMIconEntries()
    local CDMHookEngine = DDingUI.CDMHookEngine
    if not CDMHookEngine then return {} end

    local now = GetTime and GetTime() or 0
    if cdmEntryCache and (now - cdmEntryCacheTime) <= CDM_ENTRY_CACHE_TTL then
        return cdmEntryCache
    end

    CDMHookEngine:RebuildMaps()
    local iconMap = CDMHookEngine:GetIconMap()
    local result = {}
    local seenCooldownIDs = {} -- 중복 방지

    for cooldownID, icon in pairs(iconMap) do
        seenCooldownIDs[cooldownID] = true
        local spellName = CDMHookEngine:GetSpellNameForID(cooldownID)
        local tex = 134400
        local ok, texResult = pcall(function()
            if icon.Icon and icon.Icon.GetTexture then
                return icon.Icon:GetTexture()
            end
        end)
        -- [FIX] secret number 방어: GetTexture()가 secret value 반환 가능
        if ok and texResult then
            local isSafe = not (issecretvalue and issecretvalue(texResult))
            if isSafe and texResult ~= 0 and texResult ~= "" then
                tex = texResult
            end
        end

        -- [FIX] 실제 spellID 조회 — cooldownID와 spellID가 다를 수 있음
        local realSpellID = 0
        pcall(function()
            if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
                local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)
                if info then
                    -- linkedSpellIDs > overrideSpellID > spellID 우선순위
                    local linked = info.linkedSpellIDs and info.linkedSpellIDs[1]
                    realSpellID = linked or info.overrideSpellID or info.spellID or 0
                end
            end
        end)

        result[#result + 1] = {
            cooldownID = cooldownID,
            spellID = (realSpellID and realSpellID > 0) and realSpellID or cooldownID,
            name = spellName or "Unknown",
            icon = tex,
            viewerName = CDMHookEngine:GetIconSource(cooldownID) or "",
            layoutIndex = SafeCDMLayoutIndex(icon, #result + 1),
        }
    end

    -- [FIX] BuffIconCooldownViewer: 비활성 풀 프레임도 스캔 (카탈로그에 모든 버프 표시)
    -- CDM 풀의 inactiveObjects (ObjectPoolMixin 내부) 또는 뷰어 자식 프레임 스캔
    local buffViewer = _G["BuffIconCooldownViewer"]
    if buffViewer and buffViewer.itemFramePool then
        local inactiveFrames = {}
        -- ObjectPoolMixin 내부 테이블 접근 시도
        local pool = buffViewer.itemFramePool
        if pool.inactiveObjects then
            for icon in pairs(pool.inactiveObjects) do
                inactiveFrames[#inactiveFrames + 1] = icon
            end
        elseif pool.EnumerateInactive then
            for icon in pool:EnumerateInactive() do
                inactiveFrames[#inactiveFrames + 1] = icon
            end
        end
        -- fallback: 뷰어 자식 프레임 중 비활성 프레임
        if #inactiveFrames == 0 and buffViewer.GetChildren then
            local children = { buffViewer:GetChildren() }
            for _, child in ipairs(children) do
                if child.cooldownID and not seenCooldownIDs[child.cooldownID] then
                    inactiveFrames[#inactiveFrames + 1] = child
                end
            end
        end

        for _, icon in ipairs(inactiveFrames) do
            if icon.cooldownID and not seenCooldownIDs[icon.cooldownID] then
                seenCooldownIDs[icon.cooldownID] = true
                local spellName = nil
                local tex = 134400
                local realSpellID = 0

                -- C_CooldownViewer API로 정보 수집
                pcall(function()
                    if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
                        local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(icon.cooldownID)
                        if info then
                            local linked = info.linkedSpellIDs and info.linkedSpellIDs[1]
                            realSpellID = linked or info.overrideSpellID or info.spellID or 0
                            -- spellID로 이름/아이콘 조회
                            local sid = realSpellID > 0 and realSpellID or info.spellID
                            if sid and sid > 0 and C_Spell then
                                local nameResult = C_Spell.GetSpellName and C_Spell.GetSpellName(sid)
                                if nameResult and not (issecretvalue and issecretvalue(nameResult)) then
                                    spellName = "buff_" .. nameResult
                                end
                                local texResult = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid)
                                if texResult and not (issecretvalue and issecretvalue(texResult)) then
                                    tex = texResult
                                end
                            end
                        end
                    end
                end)

                -- 아이콘 텍스처 fallback
                if tex == 134400 then
                    pcall(function()
                        if icon.Icon and icon.Icon.GetTexture then
                            local t = icon.Icon:GetTexture()
                            if t and not (issecretvalue and issecretvalue(t)) and t ~= 0 and t ~= "" then
                                tex = t
                            end
                        end
                    end)
                end

                if spellName then
                    result[#result + 1] = {
                        cooldownID = icon.cooldownID,
                        spellID = (realSpellID and realSpellID > 0) and realSpellID or icon.cooldownID,
                        name = spellName,
                        icon = tex,
                        viewerName = "BuffIconCooldownViewer",
                        layoutIndex = SafeCDMLayoutIndex(icon, #result + 1),
                    }
                end
            end
        end
    end

    cdmEntryCache = result
    cdmEntryCacheTime = now
    return result
end

-- CDMHookEngine 호환 spellName 생성 (buff_ 접두사)
local function GetGSSpellName(entry)
    local name = entry.name or ""
    if name == "" or name == "Unknown" then return nil end

    if entry.viewerName == "BuffIconCooldownViewer" then
        if name:sub(1, 5) ~= "buff_" then
            return "buff_" .. name
        end
    end
    return name
end

local function GetDynamicIconTypeForEntry(entry, spellName)
    if (spellName and spellName:match("^buff_")) or (entry and entry.viewerName == "BuffIconCooldownViewer") then
        return "aura"
    end
    return "spell"
end

local function ResolveEntrySpellID(entry, spellName)
    local spellID = entry and tonumber(entry.spellID)
    if spellID and spellID > 0 then return spellID end

    local rawName = (spellName or (entry and entry.name) or ""):gsub("^buff_", "")
    if rawName ~= "" and C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(rawName)
        spellID = info and tonumber(info.spellID)
        if spellID and spellID > 0 then return spellID end
    end
    return nil
end

local GROUP_ORDER_DRAG_PREFIX = "__gs_icon_order__:"

local function MakeGroupOrderDragKey(groupName)
    return GROUP_ORDER_DRAG_PREFIX .. tostring(groupName or "")
end

local function ParseGroupOrderDragKey(groupKey)
    if type(groupKey) ~= "string" then return nil end
    return groupKey:match("^" .. GROUP_ORDER_DRAG_PREFIX .. "(.+)$")
end

local function MakeCDMOrderToken(spellName)
    if not spellName or spellName == "" then return nil end
    return "cdm:" .. spellName
end

local function MakeDynamicOrderToken(iconKey)
    if not iconKey or iconKey == "" then return nil end
    return "dyn:" .. tostring(iconKey)
end

local function BuildIconOrderMap(groupSettings)
    local orderMap = {}
    local iconOrder = groupSettings and groupSettings.iconOrder
    if type(iconOrder) == "table" then
        for i, token in ipairs(iconOrder) do
            if type(token) == "string" and token ~= "" and not orderMap[token] then
                orderMap[token] = i
            end
        end
    end
    return orderMap
end

local function SortRowsByIconOrder(groupSettings, rows)
    local orderMap = BuildIconOrderMap(groupSettings)
    local ORDER_STRIDE = 1000
    local scaledOrderMap = {}
    for token, order in pairs(orderMap) do
        scaledOrderMap[token] = order * ORDER_STRIDE
    end

    local cdmAnchors = {}
    for _, row in ipairs(rows or {}) do
        local token = row and row.token
        local rank = token and scaledOrderMap[token]
        if rank and row.kind == "cdm" then
            cdmAnchors[#cdmAnchors + 1] = {
                fallbackOrder = row.fallbackOrder or 0,
                rank = rank,
            }
        end
    end
    table.sort(cdmAnchors, function(a, b)
        return (a.fallbackOrder or 0) < (b.fallbackOrder or 0)
    end)

    local function GetImplicitCDMRank(row)
        if not row or row.kind ~= "cdm" then return nil end
        if row.token and scaledOrderMap[row.token] then return nil end
        local fallbackOrder = row.fallbackOrder or 0
        local prevAnchor, nextAnchor
        for _, anchor in ipairs(cdmAnchors) do
            if anchor.fallbackOrder < fallbackOrder then
                prevAnchor = anchor
            elseif anchor.fallbackOrder > fallbackOrder then
                nextAnchor = anchor
                break
            end
        end

        if prevAnchor and nextAnchor and nextAnchor.rank > prevAnchor.rank then
            local span = nextAnchor.fallbackOrder - prevAnchor.fallbackOrder
            if span > 0 then
                local ratio = (fallbackOrder - prevAnchor.fallbackOrder) / span
                return prevAnchor.rank + ((nextAnchor.rank - prevAnchor.rank) * ratio) + (fallbackOrder * 0.001)
            end
        elseif prevAnchor then
            return prevAnchor.rank + (ORDER_STRIDE * 0.5) + (fallbackOrder * 0.001)
        elseif nextAnchor then
            return nextAnchor.rank - (ORDER_STRIDE * 0.5) + (fallbackOrder * 0.001)
        end

        return nil
    end

    table.sort(rows, function(a, b)
        local aOrder = a.token and scaledOrderMap[a.token]
        local bOrder = b.token and scaledOrderMap[b.token]
        local aFallback = a.fallbackOrder or 0
        local bFallback = b.fallbackOrder or 0
        local aRank = aOrder or GetImplicitCDMRank(a)
        local bRank = bOrder or GetImplicitCDMRank(b)
        if aRank or bRank then
            aRank = aRank or (100000000 + aFallback)
            bRank = bRank or (100000000 + bFallback)
            if aRank ~= bRank then return aRank < bRank end
        end
        if aFallback ~= bFallback then return aFallback < bFallback end
        return tostring(a.displayName or a.token or "") < tostring(b.displayName or b.token or "")
    end)
end

local function CollectCDMRowsForGroup(groupName, allEntries, skipSpellNames)
    local rows = {}
    local gs = GetGS()
    local groupSettings = gs and gs.groups and gs.groups[groupName]
    local isBuffTargetGroup = IsBuffGroup(groupName, groupSettings)
    if not groupSettings or (groupSettings.groupType == "dynamic" and not isBuffTargetGroup) then return rows end

    local targetViewer = GROUP_VIEWER_MAP[groupName]
    local assignments = gs and gs.spellAssignments or {}
    local seen = {}

    for idx, entry in ipairs(allEntries or GetCDMIconEntries()) do
        local spellName = GetGSSpellName(entry)
        if spellName and not seen[spellName] and not (skipSpellNames and skipSpellNames[spellName]) then
            local spellID = ResolveEntrySpellID(entry, spellName)
            local isBuffSpell = IsBuffSpell(spellName, entry)
            local buffOwnedByDynamic = isBuffSpell and FindBuffDynamicSpellOwner(gs, spellID, nil)
            local isGloballyUnassigned = isBuffSpell and IsBuffSpellUnassigned(gs, spellName)
            local assigned = GetUsableSpellAssignment(gs, spellName)
            local belongsToGroup = assigned == groupName or (not assigned and targetViewer and entry.viewerName == targetViewer)
            if belongsToGroup and not isGloballyUnassigned and not buffOwnedByDynamic then
                seen[spellName] = true
                rows[#rows + 1] = {
                    kind = "cdm",
                    token = MakeCDMOrderToken(spellName),
                    spellName = spellName,
                    entry = entry,
                    isManual = assigned == groupName,
                    isBuffSpell = isBuffSpell,
                    fallbackOrder = tonumber(entry.layoutIndex) or idx,
                }
            end
        end
    end

    if assignments then
        for spellName, assignedGroup in pairs(assignments) do
            if assignedGroup == groupName and not seen[spellName] and not (skipSpellNames and skipSpellNames[spellName]) then
                seen[spellName] = true
                rows[#rows + 1] = {
                    kind = "cdm",
                    token = MakeCDMOrderToken(spellName),
                    spellName = spellName,
                    isManual = true,
                    fallbackOrder = 9000 + #rows,
                }
            end
        end
    end

    SortRowsByIconOrder(groupSettings, rows)
    return rows
end

local function CollectDynamicTokensForGroup(groupName, startFallback)
    local rows = {}
    local gs = GetGS()
    local groupSettings = gs and gs.groups and gs.groups[groupName]
    local sourceKey = groupSettings and EnsureSourceGroup(groupName)
    if not sourceKey then return rows end

    local dynDB = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.dynamicIcons
    local ciGroup = dynDB and dynDB.groups and dynDB.groups[sourceKey]
    if not ciGroup or not ciGroup.icons then return rows end

    local base = startFallback or 10000
    local seenDynamicIdentity = {}
    for iconIdx, iconKey in ipairs(ciGroup.icons) do
        local iconData = dynDB.iconData and dynDB.iconData[iconKey]
        local skipDuplicate = false
        if iconData and (iconData.type == "spell" or iconData.type == "aura") and iconData.id then
            local identity = iconData.type .. ":" .. tostring(tonumber(iconData.id) or iconData.id)
            if seenDynamicIdentity[identity] then
                skipDuplicate = true
            else
                seenDynamicIdentity[identity] = true
            end
        end

        if iconData and not skipDuplicate then
            rows[#rows + 1] = {
                kind = "dynamic",
                token = MakeDynamicOrderToken(iconKey),
                iconKey = iconKey,
                iconIdx = iconIdx,
                fallbackOrder = base + iconIdx,
            }
        end
    end

    return rows
end

local function CollectGroupOrderRows(groupName)
    local gs = GetGS()
    local groupSettings = gs and gs.groups and gs.groups[groupName]
    if not groupSettings then return {} end

    local rows = CollectCDMRowsForGroup(groupName)
    local dynamicRows = CollectDynamicTokensForGroup(groupName, 10000)
    for _, row in ipairs(dynamicRows) do
        rows[#rows + 1] = row
    end
    SortRowsByIconOrder(groupSettings, rows)
    return rows
end

local function SnapshotGroupOrderTokens(groupName)
    local tokens, seen = {}, {}
    for _, row in ipairs(CollectGroupOrderRows(groupName) or {}) do
        local token = row and row.token
        if token and not seen[token] then
            tokens[#tokens + 1] = token
            seen[token] = true
        end
    end
    return tokens, seen
end

local function AppendGroupOrderToken(groupName, beforeTokens, token)
    if not groupName or not token then return false end
    local gs = GetGS()
    local groupSettings = gs and gs.groups and gs.groups[groupName]
    if not groupSettings then return false end

    local ordered, seen = {}, {}
    for _, existing in ipairs(beforeTokens or {}) do
        if existing and not seen[existing] then
            ordered[#ordered + 1] = existing
            seen[existing] = true
        end
    end
    if not seen[token] then
        ordered[#ordered + 1] = token
    end

    groupSettings.iconOrder = ordered
    if DDingUI.SpecProfiles and DDingUI.SpecProfiles.MarkDirty then
        DDingUI.SpecProfiles:MarkDirty()
    end
    return true
end

function DDingUI:ReorderGroupSystemIcon(groupKey, sourceToken, targetToken, insertAfter)
    local groupName = ParseGroupOrderDragKey(groupKey)
    if not groupName or not sourceToken or not targetToken or sourceToken == targetToken then
        return false
    end

    local gs = GetGS()
    local groupSettings = gs and gs.groups and gs.groups[groupName]
    if not groupSettings then return false end

    local rows = CollectGroupOrderRows(groupName)
    if #rows == 0 then return false end

    local ordered = {}
    local srcIdx, dstIdx
    local seen = {}
    for _, row in ipairs(rows) do
        local token = row.token
        if token and not seen[token] then
            ordered[#ordered + 1] = token
            seen[token] = true
            if token == sourceToken then srcIdx = #ordered end
            if token == targetToken then dstIdx = #ordered end
        end
    end

    if not srcIdx or not dstIdx or srcIdx == dstIdx then return false end

    local moving = table.remove(ordered, srcIdx)
    if srcIdx < dstIdx then
        dstIdx = dstIdx - 1
    end

    local insertIdx = insertAfter and (dstIdx + 1) or dstIdx
    if insertIdx < 1 then insertIdx = 1 end
    if insertIdx > #ordered + 1 then insertIdx = #ordered + 1 end
    table.insert(ordered, insertIdx, moving)
    groupSettings.iconOrder = ordered

    RefreshGroupSystem()
    if DDingUI.SpecProfiles and DDingUI.SpecProfiles.SaveCurrentSpec then
        DDingUI.SpecProfiles:SaveCurrentSpec()
    end
    return true
end

function DDingUI:ResetGroupSystemIconOrder(groupName)
    local gs = GetGS()
    local groupSettings = gs and gs.groups and gs.groups[groupName]
    if not groupSettings then return false end

    groupSettings.iconOrder = nil
    InvalidateCDMIconEntryCache()
    RefreshGroupSystem()
    if DDingUI.SpecProfiles and DDingUI.SpecProfiles.SaveCurrentSpec then
        DDingUI.SpecProfiles:SaveCurrentSpec()
    end
    SoftRefreshDynamicIcons()
    return true
end

local function FindDynamicIconInSourceGroup(sourceKey, iconType, spellID)
    if not sourceKey or not iconType or not spellID then return nil end
    local dynDB = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.dynamicIcons
    local dynGroup = dynDB and dynDB.groups and dynDB.groups[sourceKey]
    local iconDataDB = dynDB and dynDB.iconData
    if not dynGroup or not dynGroup.icons or not iconDataDB then return nil end

    local wantedID = tonumber(spellID) or spellID
    for _, iconKey in ipairs(dynGroup.icons) do
        local iconData = iconDataDB[iconKey]
        if iconData and iconData.type == iconType then
            local existingID = tonumber(iconData.id) or iconData.id
            if existingID == wantedID or tostring(existingID) == tostring(wantedID) then
                return iconKey
            end
        end
    end
    return nil
end

local function PruneDuplicateDynamicSpellIcons(sourceKey)
    if not sourceKey or DDingUI._pruningDynamicSpellIcons then return end
    local dynDB = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.dynamicIcons
    local dynGroup = dynDB and dynDB.groups and dynDB.groups[sourceKey]
    local iconDataDB = dynDB and dynDB.iconData
    local ci = DDingUI.CustomIcons
    if not dynGroup or not dynGroup.icons or not iconDataDB or not ci or not ci.RemoveDynamicIcon then return end

    local seen = {}
    local duplicates = {}
    for _, iconKey in ipairs(dynGroup.icons) do
        local iconData = iconDataDB[iconKey]
        if iconData and (iconData.type == "spell" or iconData.type == "aura") and iconData.id then
            local identity = iconData.type .. ":" .. tostring(tonumber(iconData.id) or iconData.id)
            if seen[identity] then
                duplicates[#duplicates + 1] = iconKey
            else
                seen[identity] = iconKey
            end
        end
    end

    if #duplicates == 0 then return end
    DDingUI._pruningDynamicSpellIcons = true
    for _, iconKey in ipairs(duplicates) do
        ci:RemoveDynamicIcon(iconKey)
    end
    DDingUI._pruningDynamicSpellIcons = nil
end

local function AddOrReuseDynamicSpellIcon(groupName, iconType, spellID, spellName)
    local sourceKey = EnsureSourceGroup(groupName)
    if not sourceKey then return nil, nil, false end

    local gs = GetGS()
    local groupSettings = gs and gs.groups and gs.groups[groupName]
    local isBuffTarget = IsBuffGroup(groupName, groupSettings) and IsBuffSpell(spellName, { viewerName = iconType == "aura" and "BuffIconCooldownViewer" or nil })
    if isBuffTarget then
        RemoveBuffDynamicSpellCopies(spellID, groupName)
        ClearBuffSpellUnassigned(spellName)
        if gs and gs.spellAssignments and spellName then
            gs.spellAssignments[spellName] = nil
        end
    end

    PruneDuplicateDynamicSpellIcons(sourceKey)
    local existingKey = FindDynamicIconInSourceGroup(sourceKey, iconType, spellID)
    if existingKey then
        return existingKey, sourceKey, true
    end

    local ci = DDingUI.CustomIcons
    if not ci or not ci.AddDynamicIcon then return nil, sourceKey, false end

    local iconKey = ci:AddDynamicIcon({
        type = iconType,
        id = spellID,
        settings = {
            sourceSpellName = spellName,
            copiedFromCDM = true,
        },
    })
    if iconKey then
        ci:MoveIconToGroup(iconKey, sourceKey)
    end
    return iconKey, sourceKey, false
end

local function ClearDynamicSpellAssignment(groupName, spellName)
    if not groupName or not spellName then return end
    local gs = GetGS()
    local group = gs and gs.groups and gs.groups[groupName]
    if not group or group.groupType ~= "dynamic" then return end
    if gs.spellAssignments and gs.spellAssignments[spellName] == groupName then
        gs.spellAssignments[spellName] = nil
    end
end

-- [REFACTOR] 인라인 그리드 업데이트 (groupName 인자로 받음)
local function GetSpellCandidateViewers(groupName, groupSettings)
    local targetViewer = GROUP_VIEWER_MAP[groupName]
    if targetViewer then
        return { targetViewer }
    end

    local category = GetGroupCategory and GetGroupCategory(groupName)
    if category == "buff" then
        return { "BuffIconCooldownViewer" }
    elseif category == "skill" then
        return { "EssentialCooldownViewer", "UtilityCooldownViewer" }
    end
    return { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer" }
end

local function BuildUnassignedSpellRows(groupName)
    local rows = {}
    local gs = GetGS()
    local groupSettings = gs and gs.groups and gs.groups[groupName]
    if not groupSettings then return rows end
    ConvertCopiedBuffDynamicIconsToAssignments(groupName, groupSettings)

    local isDynamicGroup = groupSettings.groupType == "dynamic"
    local isBuffPoolGroup = IsBuffGroup(groupName, groupSettings)
    local sourceKey = isDynamicGroup and EnsureSourceGroup(groupName) or nil
    local viewers = GetSpellCandidateViewers(groupName, groupSettings)
    local viewerSet = {}
    for _, viewerKey in ipairs(viewers) do
        viewerSet[viewerKey] = true
    end

    local targetViewer = GROUP_VIEWER_MAP[groupName]
    local seen = {}
    for idx, entry in ipairs(GetCDMIconEntries()) do
        local viewerName = entry and entry.viewerName
        if viewerName and viewerSet[viewerName] then
            local spellName = GetGSSpellName(entry)
            if spellName and not seen[spellName] then
                seen[spellName] = true
                local assigned = GetUsableSpellAssignment(gs, spellName)
                local defaultAssigned = (not assigned) and targetViewer and viewerName == targetViewer
                local belongsToGroup = assigned == groupName or defaultAssigned
                local iconType = GetDynamicIconTypeForEntry(entry, spellName)
                local spellID = ResolveEntrySpellID(entry, spellName)
                local isBuffEntry = isBuffPoolGroup and IsBuffSpell(spellName, entry)
                local dynamicBuffOwner = isBuffEntry and FindBuffDynamicSpellOwner(gs, spellID, nil)
                local sharedBuffUnassigned = isBuffEntry and IsBuffSpellUnassigned(gs, spellName)
                local include

                if isBuffEntry then
                    include = sharedBuffUnassigned and not assigned and not dynamicBuffOwner
                elseif isDynamicGroup then
                    include = sourceKey and spellID and spellID > 0 and not FindDynamicIconInSourceGroup(sourceKey, iconType, spellID)
                else
                    include = not belongsToGroup
                end

                if include then
                    rows[#rows + 1] = {
                        entry = entry,
                        spellName = spellName,
                        spellID = spellID,
                        iconType = iconType,
                        iconTex = entry.icon or 134400,
                        displayName = ((entry.name or spellName or "Unknown"):gsub("^buff_", "")),
                        assignedGroup = assigned,
                        isDynamicTarget = isDynamicGroup and not isBuffEntry,
                        isBuffShared = isBuffEntry == true,
                        fallbackOrder = tonumber(entry.layoutIndex) or idx,
                    }
                end
            end
        end
    end

    table.sort(rows, function(a, b)
        local aOrder = a.fallbackOrder or 0
        local bOrder = b.fallbackOrder or 0
        if aOrder ~= bOrder then return aOrder < bOrder end
        return tostring(a.displayName or a.spellName or "") < tostring(b.displayName or b.spellName or "")
    end)
    return rows
end

local function AssignUnassignedSpellRow(groupName, row)
    if not groupName or not row or not row.spellName then return false end

    if row.isDynamicTarget then
        local spellID = row.spellID
        if not spellID or spellID <= 0 then return false end
        local iconKey = AddOrReuseDynamicSpellIcon(groupName, row.iconType or "spell", spellID, row.spellName)
        if iconKey then
            ClearDynamicSpellAssignment(groupName, row.spellName)
            ClearBuffSpellUnassigned(row.spellName)
            return true
        end
        return false
    end

    local GroupMgr = DDingUI.GroupManager
    if not GroupMgr or not GroupMgr.AssignSpell then return false end
    return GroupMgr:AssignSpell(row.spellName, groupName) == true
end

local function UpdateGroupAssignGrid(parent, groupName)
    if not parent or not parent._grids then return end

    local allEntries = GetCDMIconEntries()
    local gs = GetGS()
    local assignments = gs and gs.spellAssignments or {}
    local groupSettings = gs and gs.groups and gs.groups[groupName]
    local isDynamicGroup = groupSettings and groupSettings.groupType == "dynamic"
    local sourceKey = (groupSettings and isDynamicGroup) and EnsureSourceGroup(groupName) or nil

    for _, grid in ipairs(parent._grids) do
        local targetViewer = grid._viewerKey
        local entries = {}
        for _, entry in ipairs(allEntries) do
            if entry.viewerName == targetViewer then
                entries[#entries + 1] = entry
            end
        end

        for i, btn in ipairs(grid._buttons) do
            local entry = entries[i]
            if entry then
                btn.icon:SetTexture(entry.icon or 134400)
                btn.icon:SetAlpha(1.0)
                btn.entry = entry
                btn.spellName = GetGSSpellName(entry)

                -- 할당 상태 확인
                local assigned = GetUsableSpellAssignment(gs, btn.spellName)
                local defaultAssigned = (not assigned) and (not isDynamicGroup) and targetViewer and entry.viewerName == targetViewer
                local hasDynamicCopy = false
                if isDynamicGroup and sourceKey then
                    local iconType = GetDynamicIconTypeForEntry(entry, btn.spellName)
                    local spellID = ResolveEntrySpellID(entry, btn.spellName)
                    hasDynamicCopy = FindDynamicIconInSourceGroup(sourceKey, iconType, spellID) ~= nil
                end

                if isDynamicGroup then
                    if hasDynamicCopy then
                        btn:SetBackdropBorderColor(0.3, 1, 0.3, 1)
                        btn.checkmark:Show()
                    else
                        btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
                        btn.checkmark:Hide()
                    end
                elseif assigned == groupName or defaultAssigned then
                    -- 이 그룹에 할당됨 → 골드 테두리 + 체크마크
                    btn:SetBackdropBorderColor(1, 0.82, 0, 1)
                    btn.checkmark:Show()
                elseif assigned then
                    -- 다른 그룹에 할당됨 → 딤 + 붉은 테두리
                    btn:SetBackdropBorderColor(0.6, 0.2, 0.2, 1)
                    btn.icon:SetAlpha(0.5)
                    btn.checkmark:Hide()
                else
                    -- 미할당 (자동 분류) → 기본
                    btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
                    btn.checkmark:Hide()
                end

                btn:Show()
            else
                btn.entry = nil
                btn.spellName = nil
                btn:Hide()
            end
        end
    end
end

-- ============================================================
-- [REFACTOR] 인라인 아이콘 그리드 빌더 (팝업 다이얼로그 대체)
-- 각 뷰어 탭 내부에 직접 임베드
-- ============================================================

local QUICK_ASSIGN_CATEGORIES = {
    { key = "EssentialCooldownViewer", name = "핵심 능력 (Core)" },
    { key = "UtilityCooldownViewer", name = "보조 능력 (Utility)" },
    { key = "BuffIconCooldownViewer", name = "강화 효과 (Buffs)" },
}

function DDingUI:BuildGroupAssignGridUI(parent, groupName)
    if not parent or not groupName then return end

    local gridWidth = ICONS_PER_ROW * (ICON_GRID_SIZE + ICON_GRID_SPACING) - ICON_GRID_SPACING
    local gridRows = math.ceil(MAX_GRID_ICONS / ICONS_PER_ROW)
    local gridHeight = gridRows * (ICON_GRID_SIZE + ICON_GRID_SPACING) - ICON_GRID_SPACING

    -- 서브타이틀
    local subtitle = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitle:SetPoint("TOPLEFT", 0, 0)
    subtitle:SetText("아이콘을 클릭해서 이 그룹으로 끌어옵니다.")
    subtitle:SetTextColor(0.7, 0.7, 0.7)

    parent._grids = {}
    local currentY = -18

    local allEntries = GetCDMIconEntries()
    local targetViewer = GROUP_VIEWER_MAP[groupName]
    local viewersToRender = {}
    if targetViewer then
        -- CDM 기본 그룹: 해당 뷰어만
        table.insert(viewersToRender, { key = targetViewer, name = "" })
    else
        -- [FIX] 다이나믹 그룹: 카테고리별 카탈로그 필터링
        -- 카테고리 미설정(nil) 시 모든 뷰어 표시 (기존 그룹 호환성)
        local category = GetGroupCategory(groupName)
        if category == "buff" then
            -- 버프/오라 카테고리: BuffIcon 뷰어만 표시
            table.insert(viewersToRender, { key = "BuffIconCooldownViewer", name = L["Buffs Group"] or "강화 효과" })
        elseif category == "skill" then
            -- 스킬/아이템 카테고리: Essential + Utility 뷰어
            table.insert(viewersToRender, { key = "EssentialCooldownViewer", name = L["Essential Cooldowns"] or "핵심 능력" })
            table.insert(viewersToRender, { key = "UtilityCooldownViewer", name = L["Utility Cooldowns"] or "보조 능력" })
        else
            -- 카테고리 미설정: 전체 표시
            viewersToRender = QUICK_ASSIGN_CATEGORIES
        end
    end

    for idx, vInfo in ipairs(viewersToRender) do
        -- 해당 뷰어의 엔트리 필터링
        local entries = {}
        for _, entry in ipairs(allEntries) do
            if entry.viewerName == vInfo.key then
                entries[#entries + 1] = entry
            end
        end

        if #entries > 0 then
            -- 카테고리 헤더 (커스텀 그룹일 경우)
            if vInfo.name ~= "" then
                local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                header:SetPoint("TOPLEFT", 0, currentY)
                header:SetText(vInfo.name)
                currentY = currentY - 18
            end

            local gridRows = math.ceil(#entries / ICONS_PER_ROW)
            local gridHeight = gridRows * (ICON_GRID_SIZE + ICON_GRID_SPACING) - ICON_GRID_SPACING
            if gridHeight < 0 then gridHeight = 0 end

            -- 그리드 컨테이너
            local gridContainer = CreateFrame("Frame", nil, parent)
            gridContainer:SetPoint("TOPLEFT", 0, currentY)
            gridContainer:SetSize(gridWidth, gridHeight)
            gridContainer._buttons = {}
            gridContainer._viewerKey = vInfo.key
            
            for i = 1, #entries do
                local row = math.floor((i - 1) / ICONS_PER_ROW)
                local col = (i - 1) % ICONS_PER_ROW

                local btn = CreateFrame("Button", nil, gridContainer, "BackdropTemplate")
                btn:SetSize(ICON_GRID_SIZE, ICON_GRID_SIZE)
                btn:SetPoint("TOPLEFT", col * (ICON_GRID_SIZE + ICON_GRID_SPACING), -row * (ICON_GRID_SIZE + ICON_GRID_SPACING))

                btn:SetBackdrop({
                    bgFile = FLAT,
                    edgeFile = FLAT,
                    edgeSize = 1,
                })
                btn:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
                btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

                local icon = btn:CreateTexture(nil, "ARTWORK")
                icon:SetPoint("TOPLEFT", 2, -2)
                icon:SetPoint("BOTTOMRIGHT", -2, 2)
                btn.icon = icon

                -- 체크마크 오버레이
                local check = btn:CreateTexture(nil, "OVERLAY")
                check:SetSize(16, 16)
                check:SetPoint("BOTTOMRIGHT", -1, 1)
                check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
                check:Hide()
                btn.checkmark = check

                -- 호버
                btn:SetScript("OnEnter", function(self)
                    if not self.entry then return end
                    self:SetBackdropBorderColor(1, 1, 1, 1)

                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    local displayName = (self.entry.name or "Unknown"):gsub("^buff_", "")
                    GameTooltip:AddLine(displayName, 1, 0.82, 0)

                    local gsCurrent = GetGS()
                    local assigned = GetUsableSpellAssignment(gsCurrent, self.spellName)
                    local grpSettings = gsCurrent and gsCurrent.groups and gsCurrent.groups[groupName]
                    local isDynamic = grpSettings and grpSettings.groupType == "dynamic"
                    local defaultAssigned = (not assigned) and (not isDynamic) and self.entry and GROUP_VIEWER_MAP[groupName] == self.entry.viewerName
                    local hasDynamicCopy = false
                    local sourceKey = isDynamic and EnsureSourceGroup(groupName) or nil
                    if isDynamic and sourceKey then
                        local iconType = GetDynamicIconTypeForEntry(self.entry, self.spellName)
                        local spellID = ResolveEntrySpellID(self.entry, self.spellName)
                        hasDynamicCopy = FindDynamicIconInSourceGroup(sourceKey, iconType, spellID) ~= nil
                    end
                    if isDynamic and hasDynamicCopy then
                        GameTooltip:AddLine(L["Already added to this custom group"] or "이미 이 커스텀 그룹에 추가됨", 0.3, 1, 0.3)
                    elseif assigned then
                        if assigned == groupName then
                            GameTooltip:AddLine(L["Assigned to this group"] or "이 그룹에 할당됨", 0.3, 1, 0.3)
                        else
                            GameTooltip:AddLine((L["Assigned to: "] or "할당: ") .. assigned, 1, 0.5, 0.3)
                        end
                    elseif defaultAssigned then
                        GameTooltip:AddLine(L["Assigned to this group"] or "이 그룹에 할당됨", 0.3, 1, 0.3)
                        GameTooltip:AddLine(L["Auto (Default)"] or "자동 (기본)", 0.5, 0.5, 0.5)
                    else
                        GameTooltip:AddLine(L["Auto (Default)"] or "자동 (기본)", 0.5, 0.5, 0.5)
                    end

                    GameTooltip:AddLine(" ")
                    local toggleText = isDynamic
                        and (rawget(L, "Click: Add Copy") or "클릭: 커스텀 복사 추가")
                        or (rawget(L, "Click: Toggle Assignment") or "클릭: 할당 / 해제")
                    GameTooltip:AddLine(toggleText, 0, 1, 0)
                    GameTooltip:Show()
                end)

                btn:SetScript("OnLeave", function(self)
                    GameTooltip:Hide()
                    UpdateGroupAssignGrid(parent, groupName)
                end)

                btn:SetScript("OnClick", function(self)
                    if not self.spellName then return end

                    local gsCurrent = GetGS()
                    local grpSettings = gsCurrent and gsCurrent.groups and gsCurrent.groups[groupName]
                    local isDynamic = grpSettings and grpSettings.groupType == "dynamic"

                    if isDynamic then
                        -- 커스텀 그룹은 CDM 원본을 이동시키지 않고 CustomIcons 복사본만 추가한다.
                        local iconType = GetDynamicIconTypeForEntry(self.entry, self.spellName)
                        local spellID = ResolveEntrySpellID(self.entry, self.spellName)
                        if spellID and spellID > 0 then
                            local iconKey = AddOrReuseDynamicSpellIcon(groupName, iconType, spellID, self.spellName)
                            if iconKey then
                                ClearDynamicSpellAssignment(groupName, self.spellName)
                                SoftRefreshDynamicIcons()
                            end
                        else
                            print("|cffffffffDDing|r|cffffa300UI|r: |cffff0000 스펠 ID를 찾을 수 없습니다: " .. (self.spellName or "?") .. "|r")
                        end
                    else
                        -- CDM 그룹: 기존 AssignSpell 경로
                        local GroupMgr = DDingUI.GroupManager
                        if not GroupMgr then return end

                        local current = gsCurrent and gsCurrent.spellAssignments and gsCurrent.spellAssignments[self.spellName]
                        if current == groupName then
                            GroupMgr:UnassignSpell(self.spellName)
                        else
                            GroupMgr:AssignSpell(self.spellName, groupName)
                        end

                        SoftRefreshDynamicIcons()
                    end
                end)

                btn:Hide()
                table.insert(gridContainer._buttons, btn)
            end
            
            table.insert(parent._grids, gridContainer)
            currentY = currentY - gridHeight - 14 -- 간격 축소
        end
    end

    -- 새로고침 버튼 (StyleLib 스타일 적용)
    local GUI = DDingUI.GUI
    local scanBtn
    local refreshText = rawget(L, "Refresh UI Lists") or "리스트 새로고침"
    if GUI and GUI.CreateStyledButton then
        scanBtn = GUI.CreateStyledButton(parent, refreshText, 120, 24)
    else
        scanBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        scanBtn:SetSize(120, 24)
        scanBtn:SetText(refreshText)
    end
    scanBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, currentY - 6)
    scanBtn:SetScript("OnClick", function()
        InvalidateCDMIconEntryCache()
        if DDingUI.RefreshConfigGUI then
            DDingUI:RefreshConfigGUI()
        end
    end)

    -- 부모 높이 설정
    local totalHeight = -currentY + 28 + 6 + 10
    parent:SetHeight(totalHeight)

    -- 초기 업데이트
    UpdateGroupAssignGrid(parent, groupName)
end

function DDingUI:GetGroupAssignGridHeight()
    local gridRows = math.ceil(MAX_GRID_ICONS / ICONS_PER_ROW)
    local gridHeight = gridRows * (ICON_GRID_SIZE + ICON_GRID_SPACING) - ICON_GRID_SPACING
    return 18 + gridHeight + 28 + 6
end

-- ============================================================
-- [REFACTOR] Ayije CDM 영감 — 할당 목록 + Spell ID 입력 + 접힘 설정
-- 그룹 하나의 옵션 테이블 생성
-- ============================================================

-- 할당된 스펠 목록을 클릭 가능한 버튼(명령) 배열로 반환
local function BuildAssignedSpellsArgs(groupName)
    local args = {}
    local gs = GetGS()
    local groupSettings = gs and gs.groups and gs.groups[groupName]
    local count = 0
    local rows = {}
    ConvertCopiedBuffDynamicIconsToAssignments(groupName, groupSettings)

    -- 1. CDM 기본/수동 아이콘도 "할당된 목록"처럼 보여준다.
    -- 실제 DB를 강제로 채우지는 않고, 기본 뷰어 소속이면 자동 할당처럼 표시한다.
    local cdmRows = CollectCDMRowsForGroup(groupName)
    for _, row in ipairs(cdmRows) do
        local spellName = row.spellName
        local displayName = spellName and spellName:gsub("^buff_", "") or "Unknown"
        local iconTex = (row.entry and row.entry.icon) or 134400

        if iconTex == 134400 and spellName then
            local ok, tex = pcall(function()
                return C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellName:gsub("^buff_", ""))
            end)
            if ok and tex and not (issecretvalue and issecretvalue(tex)) and tex ~= 0 and tex ~= "" and type(tex) == "number" then
                iconTex = tex
            end
        end

        row.displayName = displayName
        row.iconTex = iconTex
        rows[#rows + 1] = row
    end

    -- 2. 동적 그룹/하이브리드 CDM 그룹: CustomIcons 아이콘도 같은 목록에 섞는다.
    local sourceGroupKey = groupSettings and EnsureSourceGroup(groupName)
    if groupSettings and sourceGroupKey then
            local dynDB = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.dynamicIcons
            local ciGroup = dynDB and dynDB.groups and dynDB.groups[sourceGroupKey]
            if ciGroup and ciGroup.icons then
                local seenDynamicIdentity = {}
                for iconIdx, iconKey in ipairs(ciGroup.icons) do
                    local iconData = dynDB.iconData and dynDB.iconData[iconKey]
                    local skipDuplicate = false
                    if iconData and (iconData.type == "spell" or iconData.type == "aura") and iconData.id then
                        local identity = iconData.type .. ":" .. tostring(tonumber(iconData.id) or iconData.id)
                        if seenDynamicIdentity[identity] then
                            skipDuplicate = true
                        else
                            seenDynamicIdentity[identity] = true
                        end
                    end
                    if iconData and not skipDuplicate then
                        local displayName, iconTex = iconKey, 134400
                        if iconData.type == "item" then
                            local itemID = iconData.id or 0
                            if type(itemID) == "string" then itemID = tonumber(itemID) or 0 end
                            
                            -- GetItemInfoInstant는 바로 아이콘을 반환 (GetItemInfo는 캐시 대기 필요)
                            local itemIDNum, itemType, itemSubType, itemEquipLoc, icon, itemClassID, itemSubClassID = C_Item.GetItemInfoInstant(itemID)
                            -- 이름은 캐시가 안 되어있으면 nil일 수 있으므로 id 보존
                            local name = nil
                            if GetItemInfo then
                                name = GetItemInfo(itemID)
                            end
                            
                            displayName = name or ((L["Item"] or "Item") .. " " .. itemID)
                            iconTex = icon or iconTex
                        elseif iconData.type == "trinketProc" then
                            local slotID = iconData.slotID or 13
                            local itemID = GetInventoryItemID("player", slotID)
                            if itemID then
                                local itemIDNum, itemType, itemSubType, itemEquipLoc, icon = C_Item.GetItemInfoInstant(itemID)
                                local name = GetItemInfo(itemID)
                                displayName = name or ("장신구 슬롯 " .. slotID)
                                iconTex = icon or iconTex
                            else
                                displayName = "장신구 슬롯 " .. slotID
                            end
                        elseif iconData.type == "spell" or iconData.type == "aura" then
                            local spellID = iconData.id or 0
                            if type(spellID) == "string" then spellID = tonumber(spellID) or spellID end
                            
                            local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
                            if spellInfo then
                                displayName = spellInfo.name or displayName
                                iconTex = spellInfo.iconID or iconTex
                            elseif C_Spell then
                                -- fallback: 개별 API
                                local name = C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
                                local icon = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID)
                                if name then displayName = name end
                                if icon then iconTex = icon end
                            end

                            if iconTex == 134400 then
                                displayName = "Invalid Spell: " .. tostring(spellID)
                            end
                        elseif iconData.type == "racial" then
                            local ci = DDingUI.CustomIcons
                            local racialID = ci and ci.GetPlayerRacialSpellID and ci:GetPlayerRacialSpellID()
                            if racialID then
                                if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                                    local ok, overrideID = pcall(C_SpellBook.FindSpellOverrideByID, racialID)
                                    if ok and overrideID and overrideID ~= racialID then
                                        racialID = overrideID
                                    end
                                end
                                local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(racialID)
                                displayName = (info and info.name) or "Racial Trait"
                                iconTex = (info and info.iconID) or (C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(racialID)) or 134400
                            else
                                displayName = "Racial Trait"
                                iconTex = 134400
                            end
                        end

                        rows[#rows + 1] = {
                            kind = "dynamic",
                            token = MakeDynamicOrderToken(iconKey),
                            iconKey = iconKey,
                            iconIdx = iconIdx,
                            iconType = iconData.type,
                            displayName = displayName,
                            iconTex = iconTex,
                            fallbackOrder = 10000 + iconIdx,
                        }
                    end
                end
            end
    end

    SortRowsByIconOrder(groupSettings, rows)

    for _, row in ipairs(rows) do
        count = count + 1
        local iconTex = row.iconTex or 134400
        local iconStr = "|T" .. iconTex .. ":20:20:0:0:64:64:5:59:5:59|t "
        local arrowPrefix = "|cff888888[" .. count .. "]|r "

        if row.kind == "cdm" then
            local capturedSpell = row.spellName
            local capturedToken = row.token
            local capturedIsManual = row.isManual
            local capturedIsBuffSpell = row.isBuffSpell == true or IsBuffSpell(capturedSpell, row.entry)
            local capturedCanRemove = capturedIsManual == true or capturedIsBuffSpell == true
            args["cdma_" .. count] = {
                type = "execute",
                name = arrowPrefix .. iconStr .. (row.displayName or capturedSpell or "Unknown"),
                desc = capturedCanRemove
                    and ((rawget(L, "Drag to reorder | Right-click to unassign") or "드래그: 순서 변경 | 우클릭: 할당 해제") .. "\n|cffaaaaaa" .. (capturedSpell or "") .. "|r")
                    or ((rawget(L, "Default CDM icon. Drag to reorder.") or "기본 CDM 아이콘입니다. 드래그로 순서를 변경하세요.") .. "\n|cffaaaaaa" .. (capturedSpell or "") .. "|r"),
                order = 11 + (count * 0.01),
                _gridKind = "cdm",
                _gridBadge = capturedIsManual and "CDM+" or "CDM",
                _gridIconTex = iconTex,
                _gridDisplayName = row.displayName or capturedSpell or "Unknown",
                _gridCanRemove = capturedCanRemove == true,
                _dragData = {
                    groupKey = MakeGroupOrderDragKey(groupName),
                    iconKey = capturedToken,
                    iconIdx = count,
                },
                func = function()
                    if not capturedSpell then return end
                    local changed = false
                    if capturedIsBuffSpell then
                        changed = MoveBuffSpellToUnassigned(capturedSpell)
                    elseif capturedIsManual and DDingUI.GroupManager then
                        changed = DDingUI.GroupManager:UnassignSpell(capturedSpell)
                    end
                    if changed then
                        SoftRefreshDynamicIcons()
                    end
                end,
            }
        elseif row.kind == "dynamic" then
            local capturedSourceKey = groupSettings and groupSettings.sourceGroupKey
            local capturedIconKey = row.iconKey
            local useGroupOrder = groupSettings and groupSettings.groupType ~= "dynamic"
            local badge = "CUSTOM"
            if row.iconType == "item" then badge = "ITEM"
            elseif row.iconType == "slot" then badge = "SLOT"
            elseif row.iconType == "trinketProc" then badge = "PROC"
            elseif row.iconType == "aura" then badge = "AURA"
            elseif row.iconType == "spell" then badge = "SPELL"
            elseif row.iconType == "racial" then badge = "RACE" end
            args["dyna_" .. count] = {
                type = "execute",
                name = arrowPrefix .. iconStr .. (row.displayName or capturedIconKey or "Unknown"),
                desc = (rawget(L, "Drag to reorder | Right-click to remove") or "드래그: 순서 변경 | 우클릭: 삭제"),
                order = 11 + (count * 0.01),
                _gridKind = "dynamic",
                _gridBadge = badge,
                _gridIconTex = iconTex,
                _gridDisplayName = row.displayName or capturedIconKey or "Unknown",
                _gridCanRemove = true,
                _dragData = {
                    groupKey = useGroupOrder and MakeGroupOrderDragKey(groupName) or capturedSourceKey,
                    iconKey = useGroupOrder and row.token or capturedIconKey,
                    iconIdx = count,
                },
                func = function()
                    -- [FIX] 관련 spellAssignments를 먼저 제거 (RemoveDynamicIcon이 iconData를 삭제하므로)
                    local gsCur = GetGS()
                    local spellNameForUnassigned
                    local spellIDForUnassigned
                    local dynDBCur = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.dynamicIcons
                    local iconDataCur = dynDBCur and dynDBCur.iconData and dynDBCur.iconData[capturedIconKey]
                    if iconDataCur and iconDataCur.id then
                        local copiedBuffSpellName = GetCopiedCDMBuffSpellName(iconDataCur)
                        local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(iconDataCur.id)
                        if spellInfo and spellInfo.name then
                            if IsBuffGroup(groupName, groupSettings) and copiedBuffSpellName then
                                spellNameForUnassigned = copiedBuffSpellName
                                spellIDForUnassigned = tonumber(iconDataCur.id)
                            end
                            -- 이전 버그로 dynamic 그룹에 기록된 할당만 정리한다.
                            -- 다른 CDM 그룹에 사용자가 직접 할당한 값은 건드리지 않는다.
                            if gsCur and gsCur.spellAssignments then
                                local buffKey = copiedBuffSpellName or ("buff_" .. spellInfo.name)
                                if gsCur.spellAssignments[buffKey] == groupName then
                                    gsCur.spellAssignments[buffKey] = nil
                                end
                                if gsCur.spellAssignments[spellInfo.name] == groupName then
                                    gsCur.spellAssignments[spellInfo.name] = nil
                                end
                            end
                        end
                    end
                    -- 클릭 = 삭제
                    if spellIDForUnassigned then
                        RemoveBuffDynamicSpellCopies(spellIDForUnassigned, groupName)
                    end
                    if DDingUI.CustomIcons and DDingUI.CustomIcons.RemoveDynamicIcon then
                        DDingUI.CustomIcons:RemoveDynamicIcon(capturedIconKey)
                    end
                    if spellNameForUnassigned then
                        MoveBuffSpellToUnassigned(spellNameForUnassigned)
                    end
                    SoftRefreshDynamicIcons()
                end,
            }
        end
    end

    if count == 0 then
        args.emptyAssigned = {
            type = "description",
            name = "|cff888888" .. (rawget(L, "No manual assignments. Use Spell ID below.") or "수동 할당 없음. 아래 입력창을 이용하세요.") .. "|r",
            order = 11,
            width = "full",
        }
    end

    return args
end

local function GetAssignedGridRows(groupName)
    local optionArgs = BuildAssignedSpellsArgs(groupName)
    local rows = {}
    local emptyText

    for key, opt in pairs(optionArgs or {}) do
        if opt and opt.type == "execute" and opt._dragData then
            rows[#rows + 1] = {
                key = key,
                option = opt,
                order = tonumber(opt.order) or 9999,
            }
        elseif opt and opt.type == "description" and opt.name then
            emptyText = opt.name
        end
    end

    table.sort(rows, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return tostring(a.key or "") < tostring(b.key or "")
    end)

    return rows, emptyText
end

local function StripIconGridText(text)
    text = tostring(text or "")
    text = text:gsub("|T.-|t%s*", "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("^%[%d+%]%s*", "")
    return text
end

local function GetGridOptionName(opt)
    if not opt then return "Unknown" end
    if opt._gridDisplayName then return opt._gridDisplayName end
    local name = opt.name
    if type(name) == "function" then name = name() end
    return StripIconGridText(name)
end

local function GetGridOptionIcon(opt)
    if opt and opt._gridIconTex then return opt._gridIconTex end
    local name = opt and opt.name
    if type(name) == "function" then name = name() end
    local tex = name and tostring(name):match("|T([^:|]+)")
    return tonumber(tex) or tex or 134400
end

function DDingUI:GetGroupAssignedIconGridHeight(groupName, width)
    local rows = GetAssignedGridRows(groupName)
    local count = #rows
    if count == 0 then return 34 end
    local tileW, tileH, gap = 68, 72, 8
    width = tonumber(width) or 760
    local cols = math.max(1, math.floor((width - 20 + gap) / (tileW + gap)))
    cols = math.min(cols, 10)
    return math.ceil(count / cols) * (tileH + gap) + 4
end

function DDingUI:BuildGroupAssignedIconGridUI(parent, groupName)
    if not parent then return end

    local rows = GetAssignedGridRows(groupName)
    local width = parent:GetWidth()
    if not width or width < 240 then width = 760 end

    local tileW, tileH, iconSize, gap = 68, 72, 42, 8
    local cols = math.max(1, math.floor((width - 20 + gap) / (tileW + gap)))
    cols = math.min(cols, 10)

    local gf = DDingUI.GetGlobalFont and DDingUI:GetGlobalFont() or STANDARD_TEXT_FONT
    local accentR, accentG, accentB = 0.3, 0.85, 1
    local normalBorderA, hoverBorderA = 0.22, 0.9
    local dragState = { active = false }

    local function CallOptionFunc(opt)
        if opt and type(opt.func) == "function" then
            opt.func()
        end
    end

    local function RefreshGridLater()
        if DDingUI.GroupSystem and DDingUI.GroupSystem.RefreshLayout then
            DDingUI.GroupSystem:RefreshLayout()
        end
        SoftRefreshDynamicIcons()
    end

    local function CursorLocalPoint(anchor)
        if not anchor or not anchor.GetEffectiveScale then return nil, nil end
        local cx, cy = GetCursorPosition()
        local scale = anchor:GetEffectiveScale()
        if not scale or scale == 0 then scale = 1 end
        local left = anchor.GetLeft and anchor:GetLeft()
        local bottom = anchor.GetBottom and anchor:GetBottom()
        if not left or not bottom then return nil, nil end
        return cx / scale - left, cy / scale - bottom
    end

    local function PositionGhostAtCursor(ghostFrame)
        local anchor = ghostFrame and (ghostFrame._ddAnchorFrame or ghostFrame:GetParent()) or parent
        if not ghostFrame then return end
        local x, y = CursorLocalPoint(anchor)
        if not x or not y then return end

        ghostFrame:ClearAllPoints()
        ghostFrame:SetPoint("CENTER", anchor, "BOTTOMLEFT", x + 12, y - 10)
    end

    local function EnsureGhost()
        local ghost = DDingUI._assignedIconGridGhost
        if ghost then
            ghost:SetParent(parent)
            ghost._ddAnchorFrame = parent
            ghost:SetFrameLevel((parent:GetFrameLevel() or 1) + 200)
            return ghost
        end

        ghost = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        ghost:SetFrameStrata("TOOLTIP")
        ghost:SetFrameLevel((parent:GetFrameLevel() or 1) + 200)
        ghost:SetSize(170, 34)
        ghost:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
        ghost:SetBackdropColor(0.04, 0.06, 0.08, 0.92)
        ghost:SetBackdropBorderColor(accentR, accentG, accentB, 0.9)
        ghost._ddAnchorFrame = parent

        ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
        ghost.icon:SetSize(24, 24)
        ghost.icon:SetPoint("LEFT", ghost, "LEFT", 5, 0)
        ghost.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        ghost.text = ghost:CreateFontString(nil, "OVERLAY")
        ghost.text:SetFont(gf, 11, "")
        ghost.text:SetShadowOffset(1, -1)
        ghost.text:SetShadowColor(0, 0, 0, 1)
        ghost.text:SetPoint("LEFT", ghost.icon, "RIGHT", 6, 0)
        ghost.text:SetPoint("RIGHT", ghost, "RIGHT", -6, 0)
        ghost.text:SetJustifyH("LEFT")

        ghost:SetScript("OnUpdate", PositionGhostAtCursor)
        ghost:Hide()
        DDingUI._assignedIconGridGhost = ghost
        return ghost
    end

    local function InstallHover(btn, isAssigned)
        local progress, target = 0, 0
        local dur = 0.10
        local baseAlpha = isAssigned and 1 or 0.58
        local hoverAlpha = 1
        local function Apply(t)
            btn:SetAlpha(baseAlpha + (hoverAlpha - baseAlpha) * t)
            btn:SetBackdropBorderColor(
                accentR * t + 0.15 * (1 - t),
                accentG * t + 0.15 * (1 - t),
                accentB * t + 0.15 * (1 - t),
                normalBorderA + (hoverBorderA - normalBorderA) * t
            )
        end
        local function OnUpdate(self, elapsed)
            local dir = (target == 1) and 1 or -1
            progress = progress + dir * (elapsed / dur)
            if (dir == 1 and progress >= 1) or (dir == -1 and progress <= 0) then
                progress = target
                self:SetScript("OnUpdate", nil)
            end
            Apply(progress)
        end
        Apply(0)
        btn._ddGridHoverIn = function(self)
            target = 1
            self:SetScript("OnUpdate", OnUpdate)
        end
        btn._ddGridHoverOut = function(self)
            target = 0
            self:SetScript("OnUpdate", OnUpdate)
        end
    end

    local function IsDropAfterGridTarget(button)
        if not button or not button.GetLeft or not button.GetRight then return false end
        local left = button:GetLeft()
        local right = button:GetRight()
        if not left or not right then return false end

        local cursorX = GetCursorPosition()
        local scale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
        if not scale or scale == 0 then scale = 1 end
        local cursorUIX = cursorX / scale
        return cursorUIX > ((left + right) * 0.5)
    end

    local function PositionInsertIndicator(indicator, targetBtn)
        if not indicator or not targetBtn then return end

        local insertAfter = IsDropAfterGridTarget(targetBtn)
        local side = insertAfter and "RIGHT" or "LEFT"
        local offset = math.max(3, math.floor((gap or 0) * 0.5))

        indicator:ClearAllPoints()
        indicator:SetHeight(tileH + 8)
        indicator:SetFrameLevel((targetBtn:GetFrameLevel() or 1) + 20)
        indicator:SetPoint("CENTER", targetBtn, side, insertAfter and offset or -offset, 0)
        indicator._ddSide = side
    end

    local function EnsureInsertIndicator()
        local indicator = parent._ddInsertIndicator
        if indicator then return indicator end

        indicator = CreateFrame("Frame", nil, parent)
        indicator:SetSize(10, tileH + 8)
        indicator:Hide()

        indicator.glow = indicator:CreateTexture(nil, "BACKGROUND")
        indicator.glow:SetPoint("TOP", indicator, "TOP", 0, 0)
        indicator.glow:SetPoint("BOTTOM", indicator, "BOTTOM", 0, 0)
        indicator.glow:SetWidth(10)
        indicator.glow:SetColorTexture(accentR, accentG, accentB, 0.22)

        indicator.core = indicator:CreateTexture(nil, "ARTWORK")
        indicator.core:SetPoint("TOP", indicator, "TOP", 0, -2)
        indicator.core:SetPoint("BOTTOM", indicator, "BOTTOM", 0, 2)
        indicator.core:SetWidth(2)
        indicator.core:SetColorTexture(0.75, 1, 0.82, 0.95)

        indicator:SetScript("OnUpdate", function(self, elapsed)
            if not dragState.active or not self._ddTargetBtn or not self._ddTargetBtn:IsShown() then
                self:Hide()
                return
            end

            self._ddPulse = (self._ddPulse or 0) + elapsed * 6
            local pulse = (math.sin(self._ddPulse) + 1) * 0.5
            self.glow:SetAlpha(0.34 + pulse * 0.18)
            self.core:SetAlpha(0.78 + pulse * 0.22)
            PositionInsertIndicator(self, self._ddTargetBtn)
        end)

        parent._ddInsertIndicator = indicator
        return indicator
    end

    local function HideInsertIndicator()
        local indicator = parent._ddInsertIndicator
        if indicator then
            indicator._ddTargetBtn = nil
            indicator:Hide()
        end
    end

    local function ShowInsertIndicator(targetBtn)
        if not dragState.active or not targetBtn then
            HideInsertIndicator()
            return
        end

        local dropFrame = targetBtn._ddAssignedDropFrame or targetBtn
        if dropFrame == dragState.sourceBtn then
            HideInsertIndicator()
            return
        end

        local src = dragState.sourceData
        local dst = targetBtn._ddAssignedDropData or dropFrame._ddAssignedDropData
        if not src or not dst or src.groupKey ~= dst.groupKey or src.iconKey == dst.iconKey then
            HideInsertIndicator()
            return
        end

        local indicator = EnsureInsertIndicator()
        indicator._ddTargetBtn = dropFrame
        PositionInsertIndicator(indicator, dropFrame)
        indicator:Show()
    end

    local function StartDrag(btn, opt)
        if not opt or not opt._dragData then return end
        dragState.active = true
        dragState.sourceBtn = btn
        dragState.sourceData = opt._dragData
        btn:SetAlpha(0.32)

        local ghost = EnsureGhost()
        ghost.icon:SetTexture(GetGridOptionIcon(opt))
        ghost.text:SetText(GetGridOptionName(opt))
        PositionGhostAtCursor(ghost)
        ghost:Show()
    end

    local function StopDrag(btn)
        if not dragState.active then return end
        if btn then btn:SetAlpha(btn._ddBaseAlpha or 1) end
        local ghost = DDingUI._assignedIconGridGhost
        if ghost then ghost:Hide() end
        HideInsertIndicator()

        local frames = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() }
        local targetBtn
        for _, f in ipairs(frames) do
            if f and f._ddAssignedDropData and f ~= dragState.sourceBtn then
                targetBtn = f
                break
            elseif f and f:GetParent() and f:GetParent()._ddAssignedDropData and f:GetParent() ~= dragState.sourceBtn then
                targetBtn = f:GetParent()
                break
            end
        end

        if targetBtn and targetBtn._ddAssignedDropData and dragState.sourceData then
            local src = dragState.sourceData
            local dst = targetBtn._ddAssignedDropData
            if src.groupKey == dst.groupKey and src.iconKey ~= dst.iconKey then
                local dropFrame = targetBtn._ddAssignedDropFrame or targetBtn
                local insertAfter = IsDropAfterGridTarget(dropFrame)
                local handled = false
                if DDingUI.ReorderGroupSystemIcon then
                    handled = DDingUI:ReorderGroupSystemIcon(src.groupKey, src.iconKey, dst.iconKey, insertAfter) == true
                end
                if not handled and DDingUI.CustomIcons and DDingUI.CustomIcons.ReorderIconInGroup then
                    DDingUI.CustomIcons:ReorderIconInGroup(src.groupKey, src.iconKey, dst.iconKey, insertAfter)
                    handled = true
                end
                if handled then
                    RefreshGridLater()
                end
            end
        end

        dragState.active = false
        dragState.sourceBtn = nil
        dragState.sourceData = nil
    end

    if #rows == 0 then
        local msg = parent:CreateFontString(nil, "OVERLAY")
        msg:SetFont(gf, 12, "")
        msg:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -4)
        msg:SetText(emptyText or "|cff888888No assigned icons.|r")
        msg:SetTextColor(0.65, 0.65, 0.65, 1)
        parent:SetHeight(34)
        return
    end

    for idx, row in ipairs(rows) do
        local opt = row.option
        local col = (idx - 1) % cols
        local rowIdx = math.floor((idx - 1) / cols)
        local x = 10 + col * (tileW + gap)
        local y = 2 + rowIdx * (tileH + gap)
        local isDynamic = opt._gridKind == "dynamic"
        local isAssigned = isDynamic or opt._gridCanRemove

        local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
        btn:SetSize(tileW, tileH)
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
        btn:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
        btn:SetBackdropColor(0.04, 0.055, 0.07, isDynamic and 0.72 or 0.48)
        btn:SetBackdropBorderColor(0.15, 0.15, 0.15, normalBorderA)
        btn._ddAssignedDropData = opt._dragData
        btn._ddAssignedDropFrame = btn
        btn._ddBaseAlpha = isAssigned and 1 or 0.58
        btn:SetAlpha(btn._ddBaseAlpha)
        btn:RegisterForClicks("LeftButtonUp")
        btn:RegisterForDrag("LeftButton")

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(iconSize, iconSize)
        icon:SetPoint("TOP", btn, "TOP", 0, -5)
        icon:SetTexture(GetGridOptionIcon(opt))
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        local badge = btn:CreateFontString(nil, "OVERLAY")
        badge:SetFont(gf, 8, "")
        badge:SetPoint("TOPLEFT", btn, "TOPLEFT", 4, -4)
        badge:SetText(opt._gridBadge or "CDM")
        badge:SetTextColor(isDynamic and accentR or 1, isDynamic and accentG or 1, isDynamic and accentB or 1, 0.88)

        local orderText = btn:CreateFontString(nil, "OVERLAY")
        orderText:SetFont(gf, 8, "")
        orderText:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -4, -4)
        orderText:SetText(idx)
        orderText:SetTextColor(0.8, 0.8, 0.8, 0.55)

        local label = btn:CreateFontString(nil, "OVERLAY")
        label:SetFont(gf, 9, "")
        label:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", -8, -3)
        label:SetPoint("TOPRIGHT", icon, "BOTTOMRIGHT", 8, -3)
        label:SetHeight(18)
        label:SetJustifyH("CENTER")
        label:SetText(GetGridOptionName(opt))
        label:SetTextColor(0.9, 0.9, 0.9, isAssigned and 0.82 or 0.55)

        InstallHover(btn, isAssigned)

        btn:SetScript("OnEnter", function(self)
            if dragState.active and dragState.sourceBtn ~= self then
                self:SetBackdropBorderColor(0.25, 1, 0.35, 1)
                ShowInsertIndicator(self)
            else
                HideInsertIndicator()
                self:_ddGridHoverIn()
            end
            local desc = opt.desc
            if type(desc) == "function" then desc = desc() end
            if desc and desc ~= "" then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(desc, 1, 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        btn:SetScript("OnLeave", function(self)
            self:_ddGridHoverOut()
            HideInsertIndicator()
            GameTooltip:Hide()
        end)
        btn:SetScript("OnDragStart", function(self)
            StartDrag(self, opt)
        end)
        btn:SetScript("OnDragStop", function(self)
            StopDrag(self)
        end)
        btn:SetScript("OnClick", function()
            if opt._gridCanRemove then
                CallOptionFunc(opt)
            end
        end)

    end

    local totalRows = math.ceil(#rows / cols)
    parent:SetHeight(totalRows * (tileH + gap) + 4)
end

-- Runtime-shaped assigned icon preview.
-- Mirrors GroupRenderer layout rules and adds Ellesmere-style manual drag feedback.
local ASSIGNED_GRID_DRAG_THRESHOLD = 8

local ASSIGNED_DIRECTION_RULES = {
    CENTERED_HORIZONTAL = { type = "HORIZONTAL", defaultSecondary = "DOWN",  allowed = { UP = true, DOWN = true } },
    LEFT                = { type = "HORIZONTAL", defaultSecondary = "DOWN",  allowed = { UP = true, DOWN = true } },
    RIGHT               = { type = "HORIZONTAL", defaultSecondary = "DOWN",  allowed = { UP = true, DOWN = true } },
    UP                  = { type = "VERTICAL",   defaultSecondary = "RIGHT", allowed = { LEFT = true, RIGHT = true } },
    DOWN                = { type = "VERTICAL",   defaultSecondary = "RIGHT", allowed = { LEFT = true, RIGHT = true } },
    STATIC              = { type = "STATIC" },
}

local function AssignedGridNumber(value, fallback)
    value = tonumber(value)
    if value == nil then return fallback end
    return value
end

local function AssignedGridPixelSnap(value)
    return math.floor((tonumber(value) or 0) + 0.5)
end

local function AssignedGridNormalizeDirection(token)
    if not token or token == "" then return nil end
    local aliases = {
        CENTEREDHORIZONTAL = "CENTERED_HORIZONTAL",
        CENTERHORIZONTAL   = "CENTERED_HORIZONTAL",
        CENTERED           = "CENTERED_HORIZONTAL",
        CENTER             = "CENTERED_HORIZONTAL",
        CENTRED            = "CENTERED_HORIZONTAL",
        CENTRE             = "CENTERED_HORIZONTAL",
    }
    local cleaned = tostring(token):gsub("[%s%-_]+", ""):upper()
    return aliases[cleaned] or cleaned
end

local function AssignedGridAspect(settings)
    local aspect = AssignedGridNumber(settings and settings.aspectRatioCrop, nil)
    if not aspect and settings and settings.aspectRatio then
        local w, h = tostring(settings.aspectRatio):match("^(%d+%.?%d*):(%d+%.?%d*)$")
        w, h = tonumber(w), tonumber(h)
        if w and h and h ~= 0 then aspect = w / h end
    end
    if not aspect or aspect <= 0 then aspect = 1 end
    return aspect
end

local function AssignedGridRowIconSize(settings, rowIndex)
    local sizes = settings and settings.rowIconSizes
    local value = sizes and sizes[rowIndex]
    value = AssignedGridNumber(value, nil)
    if value and value > 0 then return value end
    return nil
end

local function AssignedGridIconDimensions(settings, rowIndex)
    local sizeOverride = AssignedGridRowIconSize(settings, rowIndex)
    local iconSize = (sizeOverride or AssignedGridNumber(settings and settings.iconSize, 32)) + 0.1
    local aspect = AssignedGridAspect(settings)
    local iconW, iconH = iconSize, iconSize

    if aspect > 1 then
        iconH = iconSize / aspect
    elseif aspect < 1 then
        iconW = iconSize * aspect
    end

    return math.max(1, AssignedGridPixelSnap(iconW)), math.max(1, AssignedGridPixelSnap(iconH))
end

local function AssignedGridSpacing(settings)
    return math.max(0, AssignedGridPixelSnap(AssignedGridNumber(settings and settings.spacing, 2)))
end

local function AssignedGridResolveDirections(settings)
    local primary = AssignedGridNormalizeDirection(settings and settings.direction)
        or AssignedGridNormalizeDirection(settings and settings.primaryDirection)
        or "RIGHT"
    local secondary = AssignedGridNormalizeDirection(settings and settings.growDirection)
        or AssignedGridNormalizeDirection(settings and settings.secondaryDirection)

    local rule = ASSIGNED_DIRECTION_RULES[primary]
    if not rule then
        primary = "RIGHT"
        rule = ASSIGNED_DIRECTION_RULES[primary]
    end

    local rowLimit = math.floor(AssignedGridNumber(settings and settings.rowLimit, 0) + 0.0001)
    if rowLimit < 0 then rowLimit = 0 end

    if rule.type ~= "STATIC" and rowLimit > 0 then
        if not secondary or not rule.allowed[secondary] then
            secondary = rule.defaultSecondary
        end
    else
        secondary = nil
    end

    return primary, secondary, rowLimit, rule.type
end

local function AssignedGridPreviewSettings(groupName)
    local gs = GetGS()
    local groupSettings = gs and gs.groups and gs.groups[groupName]
    return groupSettings or {}
end

local function AssignedGridBuildLayout(settings, count)
    local layout = {
        slots = {},
        width = 1,
        height = 1,
        spacing = AssignedGridSpacing(settings),
    }

    if count <= 0 then return layout end

    local primary, secondary, rowLimit, layoutType = AssignedGridResolveDirections(settings)
    layout.primary = primary
    layout.secondary = secondary
    layout.rowLimit = rowLimit
    layout.layoutType = layoutType

    local spacing = layout.spacing

    if layoutType == "VERTICAL" then
        local iconsPerColumn = rowLimit > 0 and math.max(1, rowLimit) or count
        local numColumns = math.ceil(count / iconsPerColumn)
        local columns = {}
        local totalW, maxH = 0, 0

        for column = 1, numColumns do
            local iconW, iconH = AssignedGridIconDimensions(settings, column)
            local startIndex = (column - 1) * iconsPerColumn + 1
            local endIndex = math.min(column * iconsPerColumn, count)
            local columnCount = endIndex - startIndex + 1
            local columnH = columnCount * iconH + math.max(0, columnCount - 1) * spacing

            columns[column] = {
                startIndex = startIndex,
                count = columnCount,
                width = iconW,
                height = columnH,
                iconW = iconW,
                iconH = iconH,
            }
            totalW = totalW + iconW
            if column > 1 then totalW = totalW + spacing end
            maxH = math.max(maxH, columnH)
        end

        local currentX
        if secondary == "LEFT" then
            currentX = totalW
            for column = 1, numColumns do
                local meta = columns[column]
                currentX = currentX - meta.width
                meta.x = currentX
                currentX = currentX - spacing
            end
        else
            currentX = 0
            for column = 1, numColumns do
                local meta = columns[column]
                meta.x = currentX
                currentX = currentX + meta.width + spacing
            end
        end

        for column = 1, numColumns do
            local meta = columns[column]
            local columnY = (primary == "UP") and (maxH - meta.height) or 0
            for position = 0, meta.count - 1 do
                local idx = meta.startIndex + position
                local y
                if primary == "UP" then
                    y = columnY + meta.height - meta.iconH - position * (meta.iconH + spacing)
                else
                    y = columnY + position * (meta.iconH + spacing)
                end
                layout.slots[idx] = {
                    x = AssignedGridPixelSnap(meta.x),
                    y = AssignedGridPixelSnap(y),
                    w = meta.iconW,
                    h = meta.iconH,
                    line = column,
                }
            end
        end

        layout.width = math.max(1, AssignedGridPixelSnap(totalW))
        layout.height = math.max(1, AssignedGridPixelSnap(maxH))
        return layout
    end

    local iconsPerRow = rowLimit > 0 and math.max(1, rowLimit) or count
    local numRows = math.ceil(count / iconsPerRow)
    local rows = {}
    local maxW, totalH = 0, 0

    for row = 1, numRows do
        local iconW, iconH = AssignedGridIconDimensions(settings, row)
        local startIndex = (row - 1) * iconsPerRow + 1
        local endIndex = math.min(row * iconsPerRow, count)
        local rowCount = endIndex - startIndex + 1
        local rowW = rowCount * iconW + math.max(0, rowCount - 1) * spacing

        rows[row] = {
            startIndex = startIndex,
            count = rowCount,
            width = math.max(iconW, rowW),
            iconW = iconW,
            iconH = iconH,
        }
        maxW = math.max(maxW, rows[row].width)
        totalH = totalH + iconH
        if row > 1 then totalH = totalH + spacing end
    end

    local currentY
    if secondary == "UP" then
        currentY = totalH
        for row = 1, numRows do
            local meta = rows[row]
            currentY = currentY - meta.iconH
            meta.y = currentY
            currentY = currentY - spacing
        end
    else
        currentY = 0
        for row = 1, numRows do
            local meta = rows[row]
            meta.y = currentY
            currentY = currentY + meta.iconH + spacing
        end
    end

    for row = 1, numRows do
        local meta = rows[row]
        local rowX
        if primary == "LEFT" then
            rowX = maxW - meta.width
        elseif primary == "CENTERED_HORIZONTAL" then
            rowX = (maxW - meta.width) * 0.5
        else
            rowX = 0
        end

        for position = 0, meta.count - 1 do
            local idx = meta.startIndex + position
            local x
            if primary == "LEFT" then
                x = rowX + meta.width - meta.iconW - position * (meta.iconW + spacing)
            else
                x = rowX + position * (meta.iconW + spacing)
            end
            layout.slots[idx] = {
                x = AssignedGridPixelSnap(x),
                y = AssignedGridPixelSnap(meta.y),
                w = meta.iconW,
                h = meta.iconH,
                line = row,
            }
        end
    end

    layout.width = math.max(1, AssignedGridPixelSnap(maxW))
    layout.height = math.max(1, AssignedGridPixelSnap(totalH))
    return layout
end

local function AssignedGridApplyTexCoord(texture, settings)
    local zoom = AssignedGridNumber(settings and settings.zoom, 0.08)
    if zoom < 0 then zoom = 0 end
    if zoom > 0.45 then zoom = 0.45 end

    local left, right, top, bottom = zoom, 1 - zoom, zoom, 1 - zoom
    local aspect = AssignedGridAspect(settings)
    if aspect > 1 then
        local crop = (1 - (1 / aspect)) * 0.5
        local span = bottom - top
        top = top + span * crop
        bottom = bottom - span * crop
    elseif aspect < 1 then
        local crop = (1 - aspect) * 0.5
        local span = right - left
        left = left + span * crop
        right = right - span * crop
    end

    texture:SetTexCoord(left, right, top, bottom)
end

local function AssignedGridSetEdges(edges, r, g, b, a, thickness)
    if not edges then return end
    thickness = math.max(1, AssignedGridPixelSnap(thickness or 1))
    edges[1]:SetHeight(thickness)
    edges[2]:SetHeight(thickness)
    edges[3]:SetWidth(thickness)
    edges[4]:SetWidth(thickness)
    for i = 1, 4 do
        edges[i]:SetColorTexture(r, g, b, a)
    end
end

local function AssignedGridCreateEdges(frame, layer, level)
    local edges = {}
    for i = 1, 4 do
        edges[i] = frame:CreateTexture(nil, layer or "OVERLAY", nil, level or 0)
    end
    edges[1]:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    edges[1]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    edges[2]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    edges[2]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    edges[3]:SetPoint("TOPLEFT", edges[1], "BOTTOMLEFT", 0, 0)
    edges[3]:SetPoint("BOTTOMLEFT", edges[2], "TOPLEFT", 0, 0)
    edges[4]:SetPoint("TOPRIGHT", edges[1], "BOTTOMRIGHT", 0, 0)
    edges[4]:SetPoint("BOTTOMRIGHT", edges[2], "TOPRIGHT", 0, 0)
    return edges
end

local function AssignedGridGroupOrderName(data)
    return data and ParseGroupOrderDragKey(data.groupKey)
end

local function AssignedGridCommitGroupOrder(groupName, ordered)
    local gs = GetGS()
    local groupSettings = gs and gs.groups and gs.groups[groupName]
    if not groupSettings then return false end
    groupSettings.iconOrder = ordered
    RefreshGroupSystem()
    if DDingUI.SpecProfiles and DDingUI.SpecProfiles.SaveCurrentSpec then
        DDingUI.SpecProfiles:SaveCurrentSpec()
    end
    return true
end

local function AssignedGridCommitDynamicOrder(sourceKey, orderedKeys)
    local dynDB = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.dynamicIcons
    local dynGroup = dynDB and dynDB.groups and dynDB.groups[sourceKey]
    if not dynGroup or type(dynGroup.icons) ~= "table" then return false end

    local wanted = {}
    for _, key in ipairs(orderedKeys) do
        wanted[key] = true
    end

    local nextIcons = {}
    for _, key in ipairs(orderedKeys) do
        nextIcons[#nextIcons + 1] = key
    end
    for _, key in ipairs(dynGroup.icons) do
        if not wanted[key] then
            nextIcons[#nextIcons + 1] = key
        end
    end

    dynGroup.icons = nextIcons
    SoftRefreshDynamicIcons()
    return true
end

local function SafeTextureValue(value, fallback)
    if issecretvalue and issecretvalue(value) then return fallback end
    if value and value ~= 0 and value ~= "" then return value end
    return fallback
end

local function SafeSpellTexture(spellID, fallback)
    local ok, tex = pcall(function()
        return C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID)
    end)
    return SafeTextureValue(ok and tex, fallback or 134400)
end

local function SafeItemIcon(itemID, fallback)
    local ok, tex = pcall(function()
        return C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)
    end)
    if ok and tex then return tex end
    ok, tex = pcall(function()
        local _, _, _, _, icon = C_Item.GetItemInfoInstant(itemID)
        return icon
    end)
    return SafeTextureValue(ok and tex, fallback or 134400)
end

local function ScheduleDynamicIconRefresh(iconKey)
    local attempts = 0
    local poller
    poller = C_Timer.NewTicker(0.35, function()
        attempts = attempts + 1
        local ci = DDingUI.CustomIcons
        local hasFrame = ci and ci.GetAllIconFrames and ci:GetAllIconFrames()[iconKey]
        if hasFrame or attempts >= 6 then
            if poller then poller:Cancel() end
            SoftRefreshDynamicIcons()
        end
    end)
end

local function MergeDynamicIconSettings(iconKey, settings)
    if not iconKey or type(settings) ~= "table" then return end
    local dynDB = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.dynamicIcons
    local iconData = dynDB and dynDB.iconData and dynDB.iconData[iconKey]
    if not iconData then return end
    iconData.settings = iconData.settings or {}
    for k, v in pairs(settings) do
        iconData.settings[k] = v
    end
end

local function AddDynamicPayloadToGroup(groupName, payload, settings)
    if not groupName or type(payload) ~= "table" then return false end
    local ci = DDingUI.CustomIcons
    if not ci or not ci.AddDynamicIcon then return false end

    if payload.type == "item" and payload.id and C_Item and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, payload.id)
    end

    local beforeTokens = SnapshotGroupOrderTokens(groupName)
    local sourceKey = EnsureSourceGroup(groupName)
    if not sourceKey then return false end

    local iconKey = ci:AddDynamicIcon(payload)
    if not iconKey then return false end
    if settings then
        MergeDynamicIconSettings(iconKey, settings)
    end
    ci:MoveIconToGroup(iconKey, sourceKey)
    AppendGroupOrderToken(groupName, beforeTokens, MakeDynamicOrderToken(iconKey))
    ScheduleDynamicIconRefresh(iconKey)
    return true
end

local function AddSpellIDToGroup(groupName, spellID, forcedType, settings)
    spellID = tonumber(spellID)
    if not groupName or not spellID or spellID <= 0 then return false end

    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    local name = info and info.name
    if not name or name == "" then return false end

    local gs = GetGS()
    local groupSettings = gs and gs.groups and gs.groups[groupName]
    local iconType = forcedType or (IsBuffGroup(groupName, groupSettings) and "aura" or "spell")
    local spellName = name
    if iconType == "aura" and spellName:sub(1, 5) ~= "buff_" then
        spellName = "buff_" .. spellName
    end

    local beforeTokens = SnapshotGroupOrderTokens(groupName)
    local iconKey = AddOrReuseDynamicSpellIcon(groupName, iconType, spellID, spellName)
    if not iconKey then return false end
    if settings then
        MergeDynamicIconSettings(iconKey, settings)
    end
    AppendGroupOrderToken(groupName, beforeTokens, MakeDynamicOrderToken(iconKey))
    ScheduleDynamicIconRefresh(iconKey)
    return true
end

local function AddRacialIconToGroup(groupName)
    return AddDynamicPayloadToGroup(groupName, { type = "racial", id = "racial" })
end

local function AddUnassignedRowToGroup(groupName, row)
    if not row then return false end
    local beforeTokens = SnapshotGroupOrderTokens(groupName)
    if AssignUnassignedSpellRow(groupName, row) then
        if row.spellName then
            AppendGroupOrderToken(groupName, beforeTokens, MakeCDMOrderToken(row.spellName))
        end
        SoftRefreshDynamicIcons()
        return true
    end
    return false
end

local function BuildGroupAddPopupItems(groupName, unassignedRows)
    local gs = GetGS()
    local groupSettings = gs and gs.groups and gs.groups[groupName]
    local isBuff = IsBuffGroup(groupName, groupSettings)
    local items = {}

    if isBuff then
        local bloodlustAliases = { 2825, 32182, 80353, 90355, 160452, 264667, 390386 }
        items[#items + 1] = {
            label = rawget(L, "Light's Potential") or "Light's Potential",
            icon = SafeSpellTexture(1236616),
            action = function() return AddSpellIDToGroup(groupName, 1236616, "aura", { customAuraDuration = 30, customAuraTrigger = "spellcast" }) end,
        }
        items[#items + 1] = {
            label = rawget(L, "Potion of Recklessness") or "Potion of Recklessness",
            icon = SafeSpellTexture(1236994),
            action = function() return AddSpellIDToGroup(groupName, 1236994, "aura", { customAuraDuration = 30, customAuraTrigger = "spellcast" }) end,
        }
        items[#items + 1] = {
            label = rawget(L, "Devoured Dreams") or "Devoured Dreams",
            icon = SafeSpellTexture(1239479),
            action = function() return AddSpellIDToGroup(groupName, 1239479, "aura", { customAuraDuration = 10, customAuraTrigger = "spellcast" }) end,
        }
        items[#items + 1] = {
            label = rawget(L, "Time Spiral") or "Time Spiral",
            icon = SafeSpellTexture(374968),
            action = function() return AddSpellIDToGroup(groupName, 374968, "aura", { customAuraDuration = 10, customAuraTrigger = "timespiral" }) end,
        }
        items[#items + 1] = {
            label = rawget(L, "Bloodlust / Heroism") or "Bloodlust / Heroism",
            icon = SafeSpellTexture(2825),
            action = function()
                return AddSpellIDToGroup(groupName, 2825, "aura", {
                    customAuraDuration = 40,
                    customAuraTrigger = "bloodlust",
                    auraAliases = bloodlustAliases,
                })
            end,
        }
    else
        items[#items + 1] = {
            label = rawget(L, "Trinket Slot 1") or "Trinket Slot 1",
            icon = GetInventoryItemID("player", 13) and SafeItemIcon(GetInventoryItemID("player", 13)) or 134400,
            action = function() return AddDynamicPayloadToGroup(groupName, { type = "trinketProc", slotID = 13 }) end,
        }
        items[#items + 1] = {
            label = rawget(L, "Trinket Slot 2") or "Trinket Slot 2",
            icon = GetInventoryItemID("player", 14) and SafeItemIcon(GetInventoryItemID("player", 14)) or 134400,
            action = function() return AddDynamicPayloadToGroup(groupName, { type = "trinketProc", slotID = 14 }) end,
        }
        items[#items + 1] = {
            label = rawget(L, "Racial Ability") or "Racial Ability",
            icon = 134400,
            action = function() return AddRacialIconToGroup(groupName) end,
        }
        items[#items + 1] = {
            label = rawget(L, "Potions & Healthstone") or "Potions & Healthstone",
            icon = SafeItemIcon(241304),
            submenu = {
                {
                    label = rawget(L, "Light's Potential") or "Light's Potential",
                    icon = SafeItemIcon(241308),
                    action = function()
                        return AddDynamicPayloadToGroup(groupName, { type = "item", id = 241308 }, { fallbackItems = "245898,245897,241309" })
                    end,
                },
                {
                    label = rawget(L, "Potion of Recklessness") or "Potion of Recklessness",
                    icon = SafeItemIcon(241288),
                    action = function()
                        return AddDynamicPayloadToGroup(groupName, { type = "item", id = 241288 }, { fallbackItems = "245902,245903,241289" })
                    end,
                },
                {
                    label = rawget(L, "Silvermoon Health Potion") or "Silvermoon Health Potion",
                    icon = SafeItemIcon(241304),
                    action = function()
                        return AddDynamicPayloadToGroup(groupName, { type = "item", id = 241304 }, { fallbackItems = "241305" })
                    end,
                },
                {
                    label = rawget(L, "Lightfused Mana Potion") or "Lightfused Mana Potion",
                    icon = SafeItemIcon(241300),
                    action = function()
                        return AddDynamicPayloadToGroup(groupName, { type = "item", id = 241300 }, { fallbackItems = "245917,245916,241301" })
                    end,
                },
                {
                    label = rawget(L, "Invisibility Potion") or "Invisibility Potion",
                    icon = SafeItemIcon(241302),
                    action = function()
                        return AddDynamicPayloadToGroup(groupName, { type = "item", id = 241302 })
                    end,
                },
                {
                    label = rawget(L, "Healthstone") or "Healthstone",
                    icon = SafeItemIcon(5512, 538745),
                    action = function()
                        return AddDynamicPayloadToGroup(groupName, { type = "item", id = 5512 })
                    end,
                },
                {
                    label = rawget(L, "Demonic Healthstone") or "Demonic Healthstone",
                    icon = SafeItemIcon(224464, 538745),
                    action = function()
                        return AddDynamicPayloadToGroup(groupName, { type = "item", id = 224464 })
                    end,
                },
            },
        }
    end

    if unassignedRows and #unassignedRows > 0 then
        items[#items + 1] = { separator = true, label = rawget(L, "Unassigned Spells") or "Unassigned Spells" }
        local maxRows = math.min(#unassignedRows, 14)
        for i = 1, maxRows do
            local row = unassignedRows[i]
            items[#items + 1] = {
                label = row.displayName or row.spellName or "Unknown",
                icon = row.iconTex or 134400,
                action = function() return AddUnassignedRowToGroup(groupName, row) end,
            }
        end
        if #unassignedRows > maxRows then
            items[#items + 1] = {
                label = string.format("+%d more", #unassignedRows - maxRows),
                disabled = true,
            }
        end
    end

    return items
end

local function HideGroupAddSubmenu()
    local popup = DDingUI._groupIconAddPopup
    if popup and popup.submenu then
        popup.submenu:Hide()
    end
end

local function HideGroupIconAddPopup()
    local popup = DDingUI._groupIconAddPopup
    if popup then
        HideGroupAddSubmenu()
        popup:Hide()
    end
end

local function AcquirePopupRow(parent, index, width, height)
    parent._rows = parent._rows or {}
    local row = parent._rows[index]
    if not row then
        row = CreateFrame("Button", nil, parent, "BackdropTemplate")
        row:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(22, 22)
        row.icon:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row.text = row:CreateFontString(nil, "OVERLAY")
        row.text:SetPoint("LEFT", row, "LEFT", 10, 0)
        row.text:SetPoint("RIGHT", row.icon, "LEFT", -10, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetFont(STANDARD_TEXT_FONT, 11, "")
        row.arrow = row:CreateFontString(nil, "OVERLAY")
        row.arrow:SetPoint("RIGHT", row.icon, "LEFT", -6, 0)
        row.arrow:SetFont(STANDARD_TEXT_FONT, 11, "")
        row.arrow:SetText(">")
        parent._rows[index] = row
    end
    row:SetSize(width, height)
    row:Show()
    return row
end

local function ResetPopupRows(parent, fromIndex)
    if not parent or not parent._rows then return end
    for i = fromIndex or 1, #parent._rows do
        parent._rows[i]:Hide()
        parent._rows[i]:SetScript("OnEnter", nil)
        parent._rows[i]:SetScript("OnLeave", nil)
        parent._rows[i]:SetScript("OnClick", nil)
    end
end

local function StylePopupRow(row, item, gf, accentR, accentG, accentB)
    row:SetBackdropColor(0, 0, 0, 0)
    row:SetBackdropBorderColor(0, 0, 0, 0)
    row.bg:SetColorTexture(0.04, 0.065, 0.075, 0)
    row.text:SetFont(gf, item.separator and 10 or 11, "")
    row.text:SetText(item.label or "")
    row.text:SetTextColor(item.disabled and 0.36 or (item.separator and 0.9 or 0.82), item.disabled and 0.36 or (item.separator and 0.55 or 0.82), item.disabled and 0.36 or (item.separator and 0.22 or 0.82), 1)
    if item.icon and not item.separator then
        row.icon:SetTexture(item.icon)
        row.icon:Show()
    else
        row.icon:Hide()
    end
    row.arrow:SetShown(item.submenu ~= nil)
    row.arrow:SetTextColor(accentR, accentG, accentB, 0.9)
end

local function ShowGroupAddSubmenu(ownerRow, items, gf, accentR, accentG, accentB, onDone)
    local popup = DDingUI._groupIconAddPopup
    if not popup or not ownerRow or not items then return end
    local submenu = popup.submenu
    if not submenu then
        submenu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        submenu:SetFrameStrata("TOOLTIP")
        submenu:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
        submenu:SetBackdropColor(0.025, 0.05, 0.06, 0.96)
        submenu:SetBackdropBorderColor(0.16, 0.26, 0.28, 1)
        popup.submenu = submenu
    end

    local rowW, rowH, pad = 248, 30, 8
    submenu:SetSize(rowW + pad * 2, #items * rowH + pad * 2)
    submenu:ClearAllPoints()
    submenu:SetPoint("TOPLEFT", ownerRow, "TOPRIGHT", 2, 0)
    submenu:Show()

    for i, item in ipairs(items) do
        local row = AcquirePopupRow(submenu, i, rowW, rowH)
        row:SetPoint("TOPLEFT", submenu, "TOPLEFT", pad, -(pad + (i - 1) * rowH))
        StylePopupRow(row, item, gf, accentR, accentG, accentB)
        row:SetEnabled(not item.disabled and not item.separator)
        row:SetScript("OnEnter", function(self)
            self.bg:SetColorTexture(accentR, accentG, accentB, 0.18)
        end)
        row:SetScript("OnLeave", function(self)
            self.bg:SetColorTexture(0.04, 0.065, 0.075, 0)
        end)
        row:SetScript("OnClick", function()
            if item.action and item.action() then
                HideGroupIconAddPopup()
                if onDone then onDone() end
            end
        end)
    end
    ResetPopupRows(submenu, #items + 1)
end

function DDingUI:ShowGroupIconAddPopup(owner, groupName, settings, unassignedRows, onDone)
    if not owner or not groupName then return end
    local gf = DDingUI.GetGlobalFont and DDingUI:GetGlobalFont() or STANDARD_TEXT_FONT
    local accentR, accentG, accentB = 1, 0.35, 0.12
    local popup = self._groupIconAddPopup
    if not popup then
        popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        popup:SetFrameStrata("TOOLTIP")
        popup:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
        popup:SetBackdropColor(0.025, 0.05, 0.06, 0.96)
        popup:SetBackdropBorderColor(0.16, 0.26, 0.28, 1)
        popup.edit = CreateFrame("EditBox", nil, popup, "InputBoxTemplate")
        popup.edit:SetAutoFocus(false)
        popup.edit:SetHeight(24)
        popup.edit:SetFontObject(GameFontHighlightSmall)
        popup.edit.placeholder = popup.edit:CreateFontString(nil, "OVERLAY")
        popup.edit.placeholder:SetPoint("LEFT", popup.edit, "LEFT", 4, 0)
        popup.edit.placeholder:SetTextColor(0.55, 0.62, 0.64, 1)
        popup.addButton = CreateFrame("Button", nil, popup, "BackdropTemplate")
        popup.addButton:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
        popup.addButton:SetBackdropColor(0.09, 0.13, 0.15, 1)
        popup.addButton:SetBackdropBorderColor(accentR, accentG, accentB, 0.7)
        popup.addButton.text = popup.addButton:CreateFontString(nil, "OVERLAY")
        popup.addButton.text:SetPoint("CENTER")
        popup.addButton.text:SetFont(gf, 16, "")
        popup.addButton.text:SetText("+")
        popup.addButton.text:SetTextColor(accentR, accentG, accentB, 1)
        self._groupIconAddPopup = popup
    end

    HideGroupAddSubmenu()
    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -6)
    popup._groupName = groupName
    popup._owner = owner

    local rowW, rowH, pad = 248, 30, 8
    local inputH = 30
    local items = BuildGroupAddPopupItems(groupName, unassignedRows)
    local height = pad * 2 + inputH + 4 + (#items * rowH)
    popup:SetSize(rowW + pad * 2, math.max(72, height))

    local function SubmitCustomSpell()
        local text = popup.edit:GetText()
        if AddSpellIDToGroup(groupName, tonumber(text)) then
            HideGroupIconAddPopup()
            popup.edit:SetText("")
            if onDone then onDone() end
        else
            UIErrorsFrame:AddMessage(rawget(L, "Invalid Spell") or "Invalid Spell", 1, 0.15, 0.1)
        end
    end

    popup.edit:ClearAllPoints()
    popup.edit:SetPoint("TOPLEFT", popup, "TOPLEFT", pad + 2, -pad - 2)
    popup.edit:SetSize(rowW - 34, 24)
    popup.edit:SetText("")
    popup.edit.placeholder:SetFont(gf, 11, "")
    popup.edit.placeholder:SetText(rawget(L, "Custom Spell ID") or "Custom Spell ID")
    popup.edit:SetScript("OnTextChanged", function(self)
        if (self:GetText() or "") == "" then
            self.placeholder:Show()
        else
            self.placeholder:Hide()
        end
    end)
    popup.edit:SetScript("OnEnterPressed", SubmitCustomSpell)
    popup.edit:SetScript("OnEscapePressed", HideGroupIconAddPopup)
    popup.edit.placeholder:Show()

    popup.addButton:ClearAllPoints()
    popup.addButton:SetPoint("LEFT", popup.edit, "RIGHT", 6, 0)
    popup.addButton:SetSize(26, 22)
    popup.addButton:SetScript("OnClick", SubmitCustomSpell)

    for i, item in ipairs(items) do
        local row = AcquirePopupRow(popup, i, rowW, rowH)
        row:SetPoint("TOPLEFT", popup, "TOPLEFT", pad, -(pad + inputH + 4 + (i - 1) * rowH))
        StylePopupRow(row, item, gf, accentR, accentG, accentB)
        row:SetEnabled(not item.disabled and not item.separator)
        row:SetScript("OnEnter", function(self)
            self.bg:SetColorTexture(accentR, accentG, accentB, 0.16)
            if item.submenu then
                ShowGroupAddSubmenu(self, item.submenu, gf, accentR, accentG, accentB, onDone)
            else
                HideGroupAddSubmenu()
            end
        end)
        row:SetScript("OnLeave", function(self)
            self.bg:SetColorTexture(0.04, 0.065, 0.075, 0)
        end)
        row:SetScript("OnClick", function()
            if item.action and item.action() then
                HideGroupIconAddPopup()
                if onDone then onDone() end
            end
        end)
    end
    ResetPopupRows(popup, #items + 1)

    popup:Show()
end

function DDingUI:GetGroupAssignedIconGridHeight(groupName, width)
    local rows = GetAssignedGridRows(groupName)
    local settings = AssignedGridPreviewSettings(groupName)
    local layout = AssignedGridBuildLayout(settings, #rows + 1)
    width = tonumber(width) or 760

    return math.max(34, (layout.height or 1) + 18)
end

function DDingUI:BuildGroupAssignedIconGridUI(parent, groupName)
    if not parent then return end

    local rows, emptyText = GetAssignedGridRows(groupName)
    local unassignedRows = BuildUnassignedSpellRows(groupName) or {}
    local gf = DDingUI.GetGlobalFont and DDingUI:GetGlobalFont() or STANDARD_TEXT_FONT
    local settings = AssignedGridPreviewSettings(groupName)
    local count = #rows
    local layout = AssignedGridBuildLayout(settings, count + 1)
    local width = parent:GetWidth()
    if not width or width < 240 then width = 760 end

    -- Keep the preview in the option frame's own scale. Counter-scaling it against
    -- UIParent makes WoW's mouse hit regions drift inside a scaled options window.
    local localParentW = width
    local padX, padY = 8, 6
    local startX = math.max(padX, math.floor((localParentW - layout.width) * 0.5 + 0.5))
    local startY = padY
    local accentR, accentG, accentB = 0.3, 0.85, 1
    local insertR, insertG, insertB = 0.52, 1, 0.52
    local borderSize = math.max(1, AssignedGridPixelSnap(AssignedGridNumber(settings.borderSize, 1)))
    local groupAlpha = AssignedGridNumber(settings.groupAlpha, 1)
    if groupAlpha < 0.2 then groupAlpha = 0.2 end
    local drag = {}
    local slotFrames = {}

    local assignedPreviewHeight = math.ceil(layout.height + padY * 2)
    local unassignedTileSize, unassignedGap = 34, 6
    local unassignedCols = math.max(1, math.floor((width - 16 + unassignedGap) / (unassignedTileSize + unassignedGap)))
    local unassignedGridHeight = (#unassignedRows > 0) and (math.ceil(#unassignedRows / unassignedCols) * (unassignedTileSize + unassignedGap) - unassignedGap) or 0

    parent:SetHeight(math.max(34, assignedPreviewHeight))

    local preview = CreateFrame("Frame", nil, parent)
    preview:SetSize(math.max(layout.width + startX + padX, localParentW), assignedPreviewHeight)
    preview:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    if preview.SetClipsChildren then
        preview:SetClipsChildren(false)
    end
    local staleGhost = DDingUI._assignedIconRuntimeGhost
    if staleGhost then staleGhost:Hide() end
    preview:SetScript("OnHide", function()
        local ghost = DDingUI._assignedIconRuntimeGhost
        if ghost and ghost:GetParent() == preview then
            ghost:Hide()
        end
        HideGroupIconAddPopup()
    end)
    local function CallOptionFunc(opt)
        if opt and type(opt.func) == "function" then
            opt.func()
        end
    end

    local function RefreshAfterCommit()
        RefreshGroupSystem()
        if DDingUI.GroupSystem and DDingUI.GroupSystem.RefreshLayout then
            DDingUI.GroupSystem:RefreshLayout()
        end
        SoftRefreshGroupSystemOptions(0.05)
    end

    local function OrderedDragValues()
        local values, sourceGroupKey
        for _, row in ipairs(rows) do
            local data = row.option and row.option._dragData
            if data and data.groupKey and data.iconKey then
                if not values then
                    values = {}
                    sourceGroupKey = data.groupKey
                end
                if data.groupKey ~= sourceGroupKey then
                    return nil, nil
                end
                values[#values + 1] = data.iconKey
            end
        end
        return values, sourceGroupKey
    end

    local function CommitDrag(mode, fromIdx, targetIdx)
        if not fromIdx or not targetIdx or fromIdx == targetIdx then return false end
        local ordered, sourceGroupKey = OrderedDragValues()
        if not ordered or not sourceGroupKey or not ordered[fromIdx] or not ordered[targetIdx] then
            return false
        end

        if mode == "swap" then
            ordered[fromIdx], ordered[targetIdx] = ordered[targetIdx], ordered[fromIdx]
        else
            local moving = table.remove(ordered, fromIdx)
            if targetIdx < 1 then targetIdx = 1 end
            if targetIdx > #ordered + 1 then targetIdx = #ordered + 1 end
            table.insert(ordered, targetIdx, moving)
        end

        local groupOrderName = AssignedGridGroupOrderName({ groupKey = sourceGroupKey })
        if groupOrderName then
            return AssignedGridCommitGroupOrder(groupOrderName, ordered)
        end
        return AssignedGridCommitDynamicOrder(sourceGroupKey, ordered)
    end

    local function CursorLocalPoint(anchor)
        if not anchor or not anchor.GetEffectiveScale then return nil, nil end
        local cx, cy = GetCursorPosition()
        local scale = anchor:GetEffectiveScale()
        if not scale or scale == 0 then scale = 1 end
        local left = anchor.GetLeft and anchor:GetLeft()
        local bottom = anchor.GetBottom and anchor:GetBottom()
        if not left or not bottom then return nil, nil end
        return cx / scale - left, cy / scale - bottom
    end

    local function PositionRuntimeGhostAtCursor(ghostFrame)
        local anchor = ghostFrame and (ghostFrame._ddAnchorFrame or ghostFrame:GetParent()) or preview
        if not ghostFrame then return end
        local x, y = CursorLocalPoint(anchor)
        if not x or not y then return end

        ghostFrame:ClearAllPoints()
        ghostFrame:SetPoint("CENTER", anchor, "BOTTOMLEFT", x, y)
    end

    local function EnsureGhost()
        local ghost = DDingUI._assignedIconRuntimeGhost
        if ghost then
            ghost:SetParent(preview)
            ghost._ddAnchorFrame = preview
            ghost:SetFrameLevel((preview:GetFrameLevel() or 1) + 200)
            ghost:SetScale(1)
            return ghost
        end

        ghost = CreateFrame("Frame", nil, preview)
        ghost:SetFrameStrata("TOOLTIP")
        ghost:SetFrameLevel((preview:GetFrameLevel() or 1) + 200)
        ghost:SetSize(36, 36)
        ghost:SetScale(1)
        ghost:SetAlpha(0.96)
        ghost._ddAnchorFrame = preview
        ghost.bg = ghost:CreateTexture(nil, "BACKGROUND")
        ghost.bg:SetAllPoints()
        ghost.bg:SetColorTexture(0, 0, 0, 0.42)
        ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
        ghost.icon:SetAllPoints()
        ghost.edges = AssignedGridCreateEdges(ghost, "OVERLAY", 2)
        AssignedGridSetEdges(ghost.edges, accentR, accentG, accentB, 0.95, 2)
        ghost:SetScript("OnUpdate", PositionRuntimeGhostAtCursor)
        ghost:Hide()
        DDingUI._assignedIconRuntimeGhost = ghost
        return ghost
    end

    local function CursorPreviewPoint()
        return CursorLocalPoint(preview)
    end

    local function CursorInsideFrame(frame)
        local x, y = CursorLocalPoint(frame)
        if not x or not y or not frame then return false end
        local w, h = frame:GetWidth(), frame:GetHeight()
        return x >= 0 and x <= (w or 0) and y >= 0 and y <= (h or 0)
    end

    local function SlotPreviewRect(slot)
        if not slot then return nil, nil, nil, nil end
        local previewH = preview:GetHeight()
        if not previewH then return nil, nil, nil, nil end

        local left = startX + (slot._baseX or 0) + (slot._currentOffX or 0)
        local top = previewH - (startY + (slot._baseY or 0) + (slot._currentOffY or 0))
        return left, left + (slot._w or 0), top, top - (slot._h or 0)
    end

    local insertLine = CreateFrame("Frame", nil, preview)
    insertLine:SetFrameLevel(preview:GetFrameLevel() + 100)
    insertLine.glow = insertLine:CreateTexture(nil, "BACKGROUND")
    insertLine.glow:SetAllPoints()
    insertLine.glow:SetColorTexture(insertR, insertG, insertB, 0.24)
    insertLine.core = insertLine:CreateTexture(nil, "ARTWORK")
    insertLine.core:SetColorTexture(insertR, insertG, insertB, 0.96)
    insertLine:Hide()

    local assignDropOverlay = CreateFrame("Frame", nil, preview)
    assignDropOverlay:SetAllPoints(preview)
    assignDropOverlay:SetFrameLevel(preview:GetFrameLevel() + 90)
    assignDropOverlay.bg = assignDropOverlay:CreateTexture(nil, "BACKGROUND")
    assignDropOverlay.bg:SetAllPoints()
    assignDropOverlay.bg:SetColorTexture(insertR, insertG, insertB, 0.12)
    assignDropOverlay.edges = AssignedGridCreateEdges(assignDropOverlay, "OVERLAY", 3)
    AssignedGridSetEdges(assignDropOverlay.edges, insertR, insertG, insertB, 0.95, 2)
    assignDropOverlay:Hide()

    local function ClearSlotTarget(slot)
        if not slot then return end
        slot._targetOffX = 0
        slot._targetOffY = 0
        slot._swapTarget = false
        slot:SetAlpha(slot._baseAlpha or groupAlpha)
        AssignedGridSetEdges(slot._edges, 0, 0, 0, 0.78, borderSize)
        if slot._hoverEdges then
            for i = 1, 4 do slot._hoverEdges[i]:Hide() end
        end
    end

    local function PositionSlot(slot)
        slot:ClearAllPoints()
        slot:SetPoint(
            "TOPLEFT",
            preview,
            "TOPLEFT",
            startX + slot._baseX + (slot._currentOffX or 0),
            -(startY + slot._baseY + (slot._currentOffY or 0))
        )
    end

    local function TickAnimation(dt)
        local allDone = true
        for _, slot in ipairs(slotFrames) do
            local targetX = slot._targetOffX or 0
            local targetY = slot._targetOffY or 0
            local currentX = slot._currentOffX or 0
            local currentY = slot._currentOffY or 0
            local rate = math.min(1, (dt or 0) * 16)
            currentX = currentX + (targetX - currentX) * rate
            currentY = currentY + (targetY - currentY) * rate
            if math.abs(targetX - currentX) < 0.25 then currentX = targetX end
            if math.abs(targetY - currentY) < 0.25 then currentY = targetY end
            slot._currentOffX = currentX
            slot._currentOffY = currentY
            PositionSlot(slot)
            if currentX ~= targetX or currentY ~= targetY then
                allDone = false
            end
        end
        return allDone
    end

    local function ClearDragFeedback()
        insertLine:Hide()
        assignDropOverlay:Hide()
        for _, slot in ipairs(slotFrames) do
            ClearSlotTarget(slot)
        end
    end

    local function PositionInsertLine(insertIdx)
        local beforeSlot = slotFrames[insertIdx - 1]
        local afterSlot = slotFrames[insertIdx]
        local useSlot = afterSlot or beforeSlot
        if not useSlot then
            insertLine:Hide()
            return
        end

        local horizontal = layout.layoutType ~= "VERTICAL"
        insertLine:ClearAllPoints()

        if horizontal then
            local x, y, h
            if beforeSlot and afterSlot and beforeSlot._line == afterSlot._line then
                local leftSlot = beforeSlot._baseX < afterSlot._baseX and beforeSlot or afterSlot
                local rightSlot = leftSlot == beforeSlot and afterSlot or beforeSlot
                x = (leftSlot._baseX + leftSlot._w + rightSlot._baseX) * 0.5
                y = math.min(beforeSlot._baseY, afterSlot._baseY) - 4
                h = math.max(beforeSlot._h, afterSlot._h) + 8
            else
                local sideRight = layout.primary == "LEFT"
                if afterSlot then
                    x = afterSlot._baseX + (sideRight and afterSlot._w or 0)
                    y = afterSlot._baseY - 4
                    h = afterSlot._h + 8
                else
                    x = beforeSlot._baseX + (sideRight and 0 or beforeSlot._w)
                    y = beforeSlot._baseY - 4
                    h = beforeSlot._h + 8
                end
            end

            insertLine:SetSize(8, h)
            insertLine:SetPoint("TOPLEFT", preview, "TOPLEFT", startX + x - 4, -(startY + y))
            insertLine.core:ClearAllPoints()
            insertLine.core:SetPoint("TOP", insertLine, "TOP", 0, 1)
            insertLine.core:SetPoint("BOTTOM", insertLine, "BOTTOM", 0, -1)
            insertLine.core:SetWidth(2)
        else
            local x, y, w
            if beforeSlot and afterSlot and beforeSlot._line == afterSlot._line then
                local topSlot = beforeSlot._baseY < afterSlot._baseY and beforeSlot or afterSlot
                local bottomSlot = topSlot == beforeSlot and afterSlot or beforeSlot
                y = (topSlot._baseY + topSlot._h + bottomSlot._baseY) * 0.5
                x = math.min(beforeSlot._baseX, afterSlot._baseX) - 4
                w = math.max(beforeSlot._w, afterSlot._w) + 8
            else
                local sideBottom = layout.primary ~= "UP"
                if afterSlot then
                    y = afterSlot._baseY + (sideBottom and 0 or afterSlot._h)
                    x = afterSlot._baseX - 4
                    w = afterSlot._w + 8
                else
                    y = beforeSlot._baseY + (sideBottom and beforeSlot._h or 0)
                    x = beforeSlot._baseX - 4
                    w = beforeSlot._w + 8
                end
            end

            insertLine:SetSize(w, 8)
            insertLine:SetPoint("TOPLEFT", preview, "TOPLEFT", startX + x, -(startY + y - 4))
            insertLine.core:ClearAllPoints()
            insertLine.core:SetPoint("LEFT", insertLine, "LEFT", 1, 0)
            insertLine.core:SetPoint("RIGHT", insertLine, "RIGHT", -1, 0)
            insertLine.core:SetHeight(2)
        end

        insertLine._pulse = 0
        insertLine:Show()
    end

    insertLine:SetScript("OnUpdate", function(self, elapsed)
        self._pulse = (self._pulse or 0) + (elapsed or 0) * 7
        local pulse = (math.sin(self._pulse) + 1) * 0.5
        self.glow:SetAlpha(0.22 + pulse * 0.22)
        self.core:SetAlpha(0.78 + pulse * 0.22)
    end)

    local function ApplyDragFeedback(mode, targetIdx, fromIdx)
        for _, slot in ipairs(slotFrames) do
            ClearSlotTarget(slot)
        end

        local dragged = slotFrames[fromIdx]
        if dragged then dragged:SetAlpha(0.26) end

        if mode == "swap" then
            local target = slotFrames[targetIdx]
            if target then
                target._swapTarget = true
                AssignedGridSetEdges(target._edges, insertR, insertG, insertB, 1, 2)
            end
            insertLine:Hide()
            return
        end

        local visualTarget = targetIdx
        if visualTarget > fromIdx then visualTarget = visualTarget - 1 end
        local horizontal = layout.layoutType ~= "VERTICAL"
        local axisSign
        if horizontal then
            axisSign = (layout.primary == "LEFT") and -1 or 1
        else
            axisSign = (layout.primary == "UP") and -1 or 1
        end

        local baseSlot = slotFrames[fromIdx] or slotFrames[targetIdx] or slotFrames[1]
        local nudge = 10
        if baseSlot then
            nudge = math.max(5, math.min(18, math.floor(((horizontal and baseSlot._w or baseSlot._h) + layout.spacing) * 0.25 + 0.5)))
        end

        for idx, slot in ipairs(slotFrames) do
            if idx ~= fromIdx then
                local visualIdx = idx
                if visualIdx > fromIdx then visualIdx = visualIdx - 1 end
                local shiftToEnd = visualIdx >= visualTarget
                local offset = shiftToEnd and axisSign * nudge or -axisSign * nudge
                if horizontal then
                    slot._targetOffX = offset
                    slot._targetOffY = 0
                else
                    slot._targetOffX = 0
                    slot._targetOffY = offset
                end
            end
        end

        PositionInsertLine(targetIdx)
    end

    local function FindDragTarget()
        local cursorX, cursorY = CursorPreviewPoint()
        if not cursorX or not cursorY then return nil, nil end

        local horizontal = layout.layoutType ~= "VERTICAL"
        local bestIdx, bestDist
        local pad = math.max(6, layout.spacing)

        for idx, slot in ipairs(slotFrames) do
            if idx ~= drag.fromIdx then
                local left, right, top, bottom = SlotPreviewRect(slot)
                if left and right and top and bottom then
                    local centerX = (left + right) * 0.5
                    local centerY = (top + bottom) * 0.5
                    local dx, dy = cursorX - centerX, cursorY - centerY
                    local dist = dx * dx + dy * dy
                    if not bestDist or dist < bestDist then
                        bestDist = dist
                        bestIdx = idx
                    end

                    if cursorX >= left - pad and cursorX <= right + pad and cursorY >= bottom - pad and cursorY <= top + pad then
                        if horizontal then
                            local slotW = math.max(1, right - left)
                            if math.abs(cursorX - centerX) <= math.max(5, slotW * 0.22) then
                                return "swap", idx
                            end
                            if layout.primary == "LEFT" then
                                return "insert", (cursorX < centerX) and (idx + 1) or idx
                            end
                            return "insert", (cursorX < centerX) and idx or (idx + 1)
                        end

                        local slotH = math.max(1, top - bottom)
                        if math.abs(cursorY - centerY) <= math.max(5, slotH * 0.22) then
                            return "swap", idx
                        end
                        local beforeCenter = cursorY > centerY
                        if layout.primary == "UP" then
                            return "insert", beforeCenter and (idx + 1) or idx
                        end
                        return "insert", beforeCenter and idx or (idx + 1)
                    end
                end
            end
        end

        if bestIdx then
            local slot = slotFrames[bestIdx]
            if slot then
                local left, right, top, bottom = SlotPreviewRect(slot)
                if not left or not right or not top or not bottom then return nil, nil end

                if horizontal then
                    local center = (left + right) * 0.5
                    if layout.primary == "LEFT" then
                        return "insert", (cursorX < center) and (bestIdx + 1) or bestIdx
                    end
                    return "insert", (cursorX < center) and bestIdx or (bestIdx + 1)
                end

                local center = (top + bottom) * 0.5
                local beforeCenter = cursorY > center
                if layout.primary == "UP" then
                    return "insert", beforeCenter and (bestIdx + 1) or bestIdx
                end
                return "insert", beforeCenter and bestIdx or (bestIdx + 1)
            end
        end

        return nil, nil
    end

    local function FinishDrag()
        if not drag.active then return end

        local ghost = DDingUI._assignedIconRuntimeGhost
        if ghost then ghost:Hide() end

        local didChange = false
        if drag.mode == "swap" and drag.targetIdx and drag.targetIdx ~= drag.fromIdx then
            didChange = CommitDrag("swap", drag.fromIdx, drag.targetIdx)
        elseif drag.mode == "insert" and drag.insertIdx then
            local toIdx = drag.insertIdx
            if toIdx > drag.fromIdx then toIdx = toIdx - 1 end
            if toIdx < 1 then toIdx = 1 end
            if toIdx > count then toIdx = count end
            if toIdx ~= drag.fromIdx then
                didChange = CommitDrag("move", drag.fromIdx, toIdx)
            end
        end

        drag.active = false
        drag.fromIdx = nil
        drag.mode = nil
        drag.targetIdx = nil
        drag.insertIdx = nil
        preview:SetScript("OnUpdate", function(self, elapsed)
            if TickAnimation(elapsed) then
                self:SetScript("OnUpdate", nil)
                ClearDragFeedback()
            end
        end)

        if didChange then
            RefreshAfterCommit()
        end
    end

    local function BeginDrag(slot)
        local data = slot._data
        if not data then return end

        drag.active = true
        drag.fromIdx = slot._index
        drag.mode = nil
        drag.targetIdx = nil
        drag.insertIdx = nil
        slot._ddSuppressClick = true
        GameTooltip:Hide()

        local ghost = EnsureGhost()
        ghost:SetSize(slot._w, slot._h)
        ghost.icon:SetTexture(slot._icon:GetTexture())
        AssignedGridApplyTexCoord(ghost.icon, settings)
        PositionRuntimeGhostAtCursor(ghost)
        ghost:Show()
        slot:SetAlpha(0.26)

        preview:SetScript("OnUpdate", function(self, elapsed)
            if not IsMouseButtonDown("LeftButton") then
                FinishDrag()
                return
            end

            TickAnimation(elapsed)
            local mode, targetIdx = FindDragTarget()
            local noop = false
            if mode == "swap" then
                noop = targetIdx == drag.fromIdx
            elseif mode == "insert" then
                local toIdx = targetIdx
                if toIdx > drag.fromIdx then toIdx = toIdx - 1 end
                noop = toIdx == drag.fromIdx
            end

            if mode and targetIdx and not noop then
                if mode ~= drag.mode or targetIdx ~= (mode == "swap" and drag.targetIdx or drag.insertIdx) then
                    drag.mode = mode
                    drag.targetIdx = (mode == "swap") and targetIdx or nil
                    drag.insertIdx = (mode == "insert") and targetIdx or nil
                    ApplyDragFeedback(mode, targetIdx, drag.fromIdx)
                end
            else
                drag.mode = nil
                drag.targetIdx = nil
                drag.insertIdx = nil
                ClearDragFeedback()
                local dragged = slotFrames[drag.fromIdx]
                if dragged then dragged:SetAlpha(0.26) end
            end
        end)
    end

    local function FinishUnassignedDrag()
        if not drag.active or drag.kind ~= "unassigned" then return end

        local row = drag.unassignedRow
        local overAssigned = CursorInsideFrame(preview)
        local ghost = DDingUI._assignedIconRuntimeGhost
        if ghost then ghost:Hide() end

        parent:SetScript("OnUpdate", nil)
        drag.active = false
        drag.kind = nil
        drag.unassignedRow = nil
        assignDropOverlay:Hide()

        if overAssigned and AssignUnassignedSpellRow(groupName, row) then
            RefreshAfterCommit()
        end
    end

    local function BeginUnassignedDrag(button, row)
        if drag.active or not row then return end

        drag.active = true
        drag.kind = "unassigned"
        drag.unassignedRow = row
        GameTooltip:Hide()
        if button then button:SetAlpha(0.35) end

        local ghost = EnsureGhost()
        ghost:SetSize(34, 34)
        ghost.icon:SetTexture(row.iconTex or 134400)
        AssignedGridApplyTexCoord(ghost.icon, settings)
        PositionRuntimeGhostAtCursor(ghost)
        ghost:Show()

        parent:SetScript("OnUpdate", function(self)
            if not IsMouseButtonDown("LeftButton") then
                if button then button:SetAlpha(1) end
                FinishUnassignedDrag()
                return
            end

            if CursorInsideFrame(preview) then
                assignDropOverlay:Show()
            else
                assignDropOverlay:Hide()
            end
        end)
    end

    local function SetupTooltip(slot, opt)
        local desc = opt and opt.desc
        if type(desc) == "function" then desc = desc() end
        GameTooltip:SetOwner(slot, "ANCHOR_TOP")
        GameTooltip:SetText(GetGridOptionName(opt), 1, 1, 1, 1, true)
        if desc and desc ~= "" then
            GameTooltip:AddLine(desc, 0.75, 0.75, 0.75, true)
        end
        GameTooltip:Show()
    end

    for idx, row in ipairs(rows) do
        local opt = row.option
        local pos = layout.slots[idx]
        if pos then
            local slot = CreateFrame("Button", nil, preview)
            slot:SetSize(pos.w, pos.h)
            slot._index = idx
            slot._baseX = pos.x
            slot._baseY = pos.y
            slot._currentOffX = 0
            slot._currentOffY = 0
            slot._targetOffX = 0
            slot._targetOffY = 0
            slot._w = pos.w
            slot._h = pos.h
            slot._line = pos.line
            slot._data = opt and opt._dragData
            slot._baseAlpha = groupAlpha
            slot:SetAlpha(groupAlpha)
            slot:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
            slot:SetHitRectInsets(-3, -3, -3, -3)
            PositionSlot(slot)

            local bg = slot:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.02, 0.025, 0.03, 0.75)

            local icon = slot:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints()
            icon:SetTexture(GetGridOptionIcon(opt))
            AssignedGridApplyTexCoord(icon, settings)
            slot._icon = icon

            slot._edges = AssignedGridCreateEdges(slot, "OVERLAY", 2)
            AssignedGridSetEdges(slot._edges, 0, 0, 0, 0.78, borderSize)
            slot._hoverEdges = AssignedGridCreateEdges(slot, "OVERLAY", 4)
            AssignedGridSetEdges(slot._hoverEdges, accentR, accentG, accentB, 1, 2)
            for i = 1, 4 do slot._hoverEdges[i]:Hide() end

            local orderText = slot:CreateFontString(nil, "OVERLAY")
            orderText:SetFont(gf, math.max(8, math.min(11, math.floor(pos.h * 0.28))), "OUTLINE")
            orderText:SetPoint("TOPLEFT", slot, "TOPLEFT", 2, -1)
            orderText:SetText(idx)
            orderText:SetTextColor(1, 1, 1, 0.58)

            slot:SetScript("OnEnter", function(self)
                if not drag.active then
                    for i = 1, 4 do self._hoverEdges[i]:Show() end
                    SetupTooltip(self, opt)
                end
            end)
            slot:SetScript("OnLeave", function(self)
                if not self._swapTarget then
                    for i = 1, 4 do self._hoverEdges[i]:Hide() end
                end
                GameTooltip:Hide()
            end)
            slot:SetScript("OnClick", function(self, button)
                if self._ddSuppressClick then
                    self._ddSuppressClick = nil
                    return
                end
                if (button == "RightButton" or button == "MiddleButton") and opt and opt._gridCanRemove then
                    CallOptionFunc(opt)
                end
            end)
            slot:SetScript("OnMouseDown", function(self, button)
                if button ~= "LeftButton" or drag.active or not self._data then return end
                local cx, cy = GetCursorPosition()
                self._pendingDragStartX = cx
                self._pendingDragStartY = cy
                self:SetScript("OnUpdate", function(s)
                    if not IsMouseButtonDown("LeftButton") then
                        s:SetScript("OnUpdate", nil)
                        s._pendingDragStartX = nil
                        s._pendingDragStartY = nil
                        return
                    end
                    local nx, ny = GetCursorPosition()
                    local dx = nx - (s._pendingDragStartX or nx)
                    local dy = ny - (s._pendingDragStartY or ny)
                    if dx * dx + dy * dy >= ASSIGNED_GRID_DRAG_THRESHOLD * ASSIGNED_GRID_DRAG_THRESHOLD then
                        s:SetScript("OnUpdate", nil)
                        s._pendingDragStartX = nil
                        s._pendingDragStartY = nil
                        BeginDrag(s)
                    end
                end)
            end)
            slot:SetScript("OnMouseUp", function(self, button)
                if button == "LeftButton" then
                    self:SetScript("OnUpdate", nil)
                    self._pendingDragStartX = nil
                    self._pendingDragStartY = nil
                end
            end)

            slotFrames[#slotFrames + 1] = slot
        end
    end

    local addPos = layout.slots[count + 1]
    if addPos then
        local addSlot = CreateFrame("Button", nil, preview, "BackdropTemplate")
        addSlot:SetSize(addPos.w, addPos.h)
        addSlot:SetPoint("TOPLEFT", preview, "TOPLEFT", startX + addPos.x, -(startY + addPos.y))
        addSlot:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
        addSlot:SetBackdropColor(0.05, 0.035, 0.04, 0.86)
        addSlot:SetBackdropBorderColor(1, 0.35, 0.12, 0.46)
        addSlot:RegisterForClicks("LeftButtonUp")

        local plus = addSlot:CreateFontString(nil, "OVERLAY")
        plus:SetPoint("CENTER", addSlot, "CENTER", 0, 0)
        plus:SetFont(gf, math.max(16, math.floor(math.min(addPos.w, addPos.h) * 0.58)), "")
        plus:SetText("+")
        plus:SetTextColor(1, 0.35, 0.12, 0.95)

        addSlot:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(1, 0.35, 0.12, 1)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(rawget(L, "Add Spell or Item") or "Add Spell or Item", 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        addSlot:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(1, 0.35, 0.12, 0.46)
            GameTooltip:Hide()
        end)
        addSlot:SetScript("OnClick", function(self)
            if DDingUI._groupIconAddPopup and DDingUI._groupIconAddPopup:IsShown() and DDingUI._groupIconAddPopup._owner == self then
                HideGroupIconAddPopup()
                return
            end
            DDingUI:ShowGroupIconAddPopup(self, groupName, settings, unassignedRows, RefreshAfterCommit)
        end)
    end

    if false and #unassignedRows > 0 then
        local sectionY = assignedPreviewHeight + 12
        local title = parent:CreateFontString(nil, "OVERLAY")
        title:SetFont(gf, 12, "")
        title:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -sectionY)
        title:SetText(L["Unassigned Spells"] or "할당되지 않은 스펠")
        title:SetTextColor(1, 0.55, 0.18, 1)

        local desc = parent:CreateFontString(nil, "OVERLAY")
        desc:SetFont(gf, 10, "")
        desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
        desc:SetText(L["Drag icons up to assign them to this group."] or "아이콘을 위로 드래그하면 이 그룹에 할당됩니다.")
        desc:SetTextColor(0.65, 0.65, 0.65, 1)

        local grid = CreateFrame("Frame", nil, parent)
        grid:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -(sectionY + 30))
        grid:SetSize(width - 20, unassignedGridHeight)

        for idx, unassignedRow in ipairs(unassignedRows) do
            local col = (idx - 1) % unassignedCols
            local rowIdx = math.floor((idx - 1) / unassignedCols)
            local btn = CreateFrame("Button", nil, grid)
            btn:SetSize(unassignedTileSize, unassignedTileSize)
            btn:SetPoint("TOPLEFT", grid, "TOPLEFT", col * (unassignedTileSize + unassignedGap), -rowIdx * (unassignedTileSize + unassignedGap))
            btn:SetHitRectInsets(-2, -2, -2, -2)

            btn.bg = btn:CreateTexture(nil, "BACKGROUND")
            btn.bg:SetAllPoints()
            btn.bg:SetColorTexture(0.02, 0.025, 0.03, 0.68)

            btn.icon = btn:CreateTexture(nil, "ARTWORK")
            btn.icon:SetAllPoints()
            btn.icon:SetTexture(unassignedRow.iconTex or 134400)
            AssignedGridApplyTexCoord(btn.icon, settings)

            btn.edges = AssignedGridCreateEdges(btn, "OVERLAY", 2)
            AssignedGridSetEdges(btn.edges, 0.18, 0.18, 0.18, 0.8, 1)

            btn:SetScript("OnEnter", function(self)
                if drag.active then return end
                AssignedGridSetEdges(self.edges, accentR, accentG, accentB, 1, 2)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(unassignedRow.displayName or unassignedRow.spellName or "Unknown", 1, 1, 1, 1, true)
                if unassignedRow.assignedGroup and unassignedRow.assignedGroup ~= groupName then
                    GameTooltip:AddLine((L["Assigned to: "] or "할당: ") .. tostring(unassignedRow.assignedGroup), 1, 0.55, 0.35, true)
                end
                GameTooltip:AddLine(L["Drag to assigned spells"] or "할당된 스펠 영역으로 드래그", 0.35, 1, 0.45, true)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function(self)
                AssignedGridSetEdges(self.edges, 0.18, 0.18, 0.18, 0.8, 1)
                GameTooltip:Hide()
            end)
            btn:SetScript("OnMouseDown", function(self, button)
                if button ~= "LeftButton" or drag.active then return end
                local cx, cy = GetCursorPosition()
                self._pendingDragStartX = cx
                self._pendingDragStartY = cy
                self:SetScript("OnUpdate", function(s)
                    if not IsMouseButtonDown("LeftButton") then
                        s:SetScript("OnUpdate", nil)
                        s._pendingDragStartX = nil
                        s._pendingDragStartY = nil
                        return
                    end
                    local nx, ny = GetCursorPosition()
                    local dx = nx - (s._pendingDragStartX or nx)
                    local dy = ny - (s._pendingDragStartY or ny)
                    if dx * dx + dy * dy >= ASSIGNED_GRID_DRAG_THRESHOLD * ASSIGNED_GRID_DRAG_THRESHOLD then
                        s:SetScript("OnUpdate", nil)
                        s._pendingDragStartX = nil
                        s._pendingDragStartY = nil
                        BeginUnassignedDrag(s, unassignedRow)
                    end
                end)
            end)
            btn:SetScript("OnMouseUp", function(self, button)
                if button == "LeftButton" then
                    self:SetScript("OnUpdate", nil)
                    self._pendingDragStartX = nil
                    self._pendingDragStartY = nil
                end
            end)
        end
    end
end

-- 스펠 이름/ID → GroupManager 할당용 이름 변환
local function ResolveSpellInput(input, groupName)
    if not input or input == "" then return nil end

    -- 숫자면 Spell ID로 해석
    local spellID = tonumber(input)
    if spellID then
        local ok, info = pcall(function()
            if C_Spell and C_Spell.GetSpellInfo then
                return C_Spell.GetSpellInfo(spellID)
            end
        end)
        if ok and info and info.name then
            -- 버프 뷰어 그룹이면 buff_ 접두사 추가
            local targetViewer = GROUP_VIEWER_MAP[groupName]
            if targetViewer == "BuffIconCooldownViewer" then
                return "buff_" .. info.name
            end
            return info.name
        end
        return nil -- ID를 이름으로 변환 실패
    end

    -- 문자열이면 그대로 사용 (buff_ 접두사는 사용자가 직접 지정)
    return input
end

-- 기본 3개 CDM 그룹 (삭제 불가)
local CDM_GROUPS = { ["Cooldowns"] = true, ["Buffs"] = true, ["Utility"] = true }

-- [CATEGORIZED] 뷰어 옵션을 카테고리별로 분배하기 위한 키 목록
local VIEWER_VISUAL_KEYS = {
    -- 쿨다운 스와이프
    "animationHeader", "disableSwipeAnimation",
    "auraSwipeColor", "resetAuraSwipeColor",
    -- 그림자 (텍스트에서 이동)
    "shadowHeader", "cooldownShadowOffsetX", "cooldownShadowOffsetY",
    -- 아이콘 글로우 (오라)
    "auraGlowHeader", "auraGlow", "auraGlowType", "auraGlowColor",
    "auraGlowPixelLines", "auraGlowPixelFrequency", "auraGlowPixelThickness", "auraGlowPixelLength",
    "auraGlowAutocastParticles", "auraGlowAutocastFrequency", "auraGlowAutocastScale",
    "auraGlowButtonFrequency",
    -- 아이콘 글로우 (프록)
    "procGlowHeader", "procGlowEnabled", "procGlowType", "procGlowColor",
    "procGlowPixelLines", "procGlowPixelFrequency", "procGlowPixelThickness", "procGlowPixelLength",
    "procGlowAutocastParticles", "procGlowAutocastFrequency", "procGlowAutocastScale",
    "procGlowButtonFrequency",
    -- 보조 강조 효과
    "assistHighlightHeader", "assistHighlightEnabled", "assistHighlightType",
    "assistFlipbookScale", "assistGlowType", "assistGlowColor",
    "assistGlowLines", "assistGlowFrequency", "assistGlowThickness", "assistHighlightPixelLength",
    -- 이동 애니메이션
    "motionHeader", "iconMotion", "iconMotionDuration",
    -- 엣지/블링 애니메이션
    "disableEdgeGlow", "disableBlingAnimation",
}

local VIEWER_TEXT_KEYS = {
    -- 충전/중첩 텍스트
    "chargeTextHeader", "countTextFont", "countTextSize", "countTextColor",
    "chargeTextAnchor", "countTextOffsetX", "countTextOffsetY",
    -- 쿨다운 텍스트
    "cooldownTextHeader", "cooldownFont", "cooldownFontSize", "cooldownTextColor",
    "cooldownTextAnchor", "cooldownTextOffsetX", "cooldownTextOffsetY", "cooldownTextFormat",
    -- 강화 효과 지속시간 (BuffIcon only)
    "buffDurationHeader", "durationTextAnchor", "durationTextOffsetX", "durationTextOffsetY",
    "durationTextFont", "durationTextSize", "durationTextColor",
    -- 키바인드 텍스트 (Essential/Utility only)
    "showKeybinds", "keybindHeader", "keybindFont", "keybindFontSize", "keybindFontColor",
    "keybindAnchor", "keybindOffsetX", "keybindOffsetY",
}

-- [5TAB] 뷰어 탭 전용 키 — CDM 그룹에서만 사용 (뷰어 앵커, 그룹 오프셋, 미리보기)
local VIEWER_DETAIL_KEYS = {
    -- 뷰어 앵커 설정
    "anchorHeader", "anchorDesc", "anchorFrame", "anchorPick", "anchorClear",
    "anchorPoint", "anchorOffsetX", "anchorOffsetY",
    -- 그룹 오프셋 (파티/레이드)
    "groupOffsetHeader", "partyOffsetX", "partyOffsetY", "raidOffsetX", "raidOffsetY",
    -- 미리보기
    "previewBuffIcons",
}

-- ============================================================
-- [CATEGORY] 4분류: 기본 스킬/기본 버프/커스텀 스킬/커스텀 버프
-- CDM → viewer 기반 옵션, 커스텀 → group settings 기반 옵션
-- ============================================================

local CATEGORY_VALUES = {
    ["skill"] = L["Skill / Item"] or "스킬 / 아이템",
    ["buff"]  = L["Buff / Aura"] or "버프 / 오라",
}

-- 그룹 카테고리 판별 (CDM은 뷰어로 자동, 커스텀은 설정값)
-- [FIX] 명시적 카테고리 없으면 nil 반환 (기존 그룹 호환성 보장)
GetGroupCategory = function(groupName)
    local viewerKey = GROUP_VIEWER_MAP[groupName]
    if viewerKey == "BuffIconCooldownViewer" then return "buff" end
    if viewerKey then return "skill" end -- Essential/Utility
    local gs = GetGS()
    local grp = gs and gs.groups[groupName]
    return grp and grp.groupCategory or nil
end

-- [Ayije 통합] 그룹 설정 읽기/쓰기 — 모든 그룹 동일 (groupSettings가 단일 소스)
local function GS_Range(groupName, key, name, order, default, min, max, step, extra)
    local opt = {
        type = "range", name = name, order = order, width = "full",
        min = min, max = max, step = step,
        get = function()
            local gs = GetGS(); local g = gs and gs.groups[groupName]
            return g and g[key] or default
        end,
        set = function(_, val)
            local gs = GetGS()
            if gs and gs.groups[groupName] then gs.groups[groupName][key] = val end
            RefreshGroupSystem()
        end,
    }
    if extra then for k, v in pairs(extra) do opt[k] = v end end
    return opt
end

local function GS_Color(groupName, key, name, order, default)
    return {
        type = "color", name = name, order = order, width = "full", hasAlpha = true,
        get = function()
            local gs = GetGS(); local c = gs and gs.groups[groupName] and gs.groups[groupName][key] or default
            return c[1], c[2], c[3], c[4] or 1
        end,
        set = function(_, r, g, b, a)
            local gs = GetGS()
            if gs and gs.groups[groupName] then gs.groups[groupName][key] = {r, g, b, a or 1}; RefreshGroupSystem() end
        end,
    }
end

local function GS_Select(groupName, key, name, order, default, values)
    return {
        type = "select", name = name, order = order, width = "full", values = values,
        get = function()
            local gs = GetGS(); local g = gs and gs.groups[groupName]
            return g and g[key] or default
        end,
        set = function(_, val)
            local gs = GetGS()
            if gs and gs.groups[groupName] then gs.groups[groupName][key] = val end
            RefreshGroupSystem()
        end,
    }
end

local function GS_Toggle(groupName, key, name, order, default)
    return {
        type = "toggle", name = name, order = order, width = "full",
        get = function()
            local gs = GetGS(); local g = gs and gs.groups[groupName]
            if g and g[key] ~= nil then return g[key] end
            return default
        end,
        set = function(_, val)
            local gs = GetGS()
            if gs and gs.groups[groupName] then gs.groups[groupName][key] = val; RefreshGroupSystem() end
        end,
    }
end

local ANCHOR_POINTS = {
    TOPLEFT = "TOPLEFT", TOP = "TOP", TOPRIGHT = "TOPRIGHT",
    LEFT = "LEFT", CENTER = "CENTER", RIGHT = "RIGHT",
    BOTTOMLEFT = "BOTTOMLEFT", BOTTOM = "BOTTOM", BOTTOMRIGHT = "BOTTOMRIGHT",
}

-- [5TAB] 뷰어 옵션 복사 + order 재지정 헬퍼
-- ViewerOptions의 원래 order 값이 높아(51~144) 섹션 헤더와 충돌하므로 반드시 재지정
local function CopyVO(vo, key, newOrder, layoutOnly)
    if not vo[key] then return nil end
    local opt = {}
    for k, v in pairs(vo[key]) do opt[k] = v end
    opt.order = newOrder
    -- 원본 setter 후 GroupSystem 갱신
    local origSet = opt.set
    if origSet then
        opt.set = function(info, ...)
            origSet(info, ...)
            -- [12.0.1] layoutOnly: 크기/간격/방향 변경은 레이아웃만 갱신 (깜빡임 방지)
            if layoutOnly then
                RefreshGroupLayout()
            else
                RefreshGroupSystem()
            end
        end
    end
    return opt
end

-- [CATEGORY] 커스텀 그룹용 시각 효과 옵션 빌드
local function BuildCustomVisualArgs(groupName)
    local isBuffGroup = GetGroupCategory(groupName) == "buff"

    return {
        -- 쿨다운 스와이프
        swipeHeader = { type = "header", name = L["Cooldown Swipe"] or "쿨다운 스와이프", order = 1 },
        swipeReverse = GS_Toggle(groupName, "swipeReverse", L["Reverse Swipe"] or "스와이프 반전", 2, true),
        swipeColor = GS_Color(groupName, "swipeColor", L["Swipe Color"] or "스와이프 색상", 3, {0,0,0,0.8}),
        disableSwipeAnimation = GS_Toggle(groupName, "disableSwipeAnimation", L["Disable Swipe Animation"] or "스와이프 애니메이션 비활성화", 4, false),
        -- 그림자
        shadowHeader = { type = "header", name = L["Shadow"] or "그림자", order = 8 },
        cooldownShadowOffsetX = GS_Range(groupName, "cooldownShadowOffsetX", L["Shadow X"] or "그림자 X", 9, 1, -5, 5, 0.5),
        cooldownShadowOffsetY = GS_Range(groupName, "cooldownShadowOffsetY", L["Shadow Y"] or "그림자 Y", 10, -1, -5, 5, 0.5),
        -- 글로우 효과
        glowHeader = { type = "header", name = L["Glow Effects"] or "글로우 효과", order = 15 },
        auraGlow = GS_Toggle(groupName, "auraGlow", L["Aura Glow"] or "오라 글로우", 16, false),
        procGlowEnabled = GS_Toggle(groupName, "procGlowEnabled", L["Proc Glow"] or "발동 글로우", 17, true),
        -- 지속 효과 숨기기 (EllesmereUI hideActive 이식)
        hideActiveState = GS_Toggle(groupName, "hideActiveState", L["Hide Active State"] or "지속 효과 숨기기", 18, false),
        hideActiveStateDesc = {
            type = "description", order = 18.5,
            name = "|cff888888" .. (L["Hide active buff/aura overlay when the effect is active. The icon remains visible but the active state animation (glow, swipe color) is suppressed."] or "효과가 활성화되었을 때 활성 상태 오버레이(글로우, 스와이프 색상)를 숨깁니다. 아이콘은 보이지만 활성 표시만 비활성화됩니다.") .. "|r",
        },
        -- 보조 강조 효과 (Assist Highlight)
        assistHighlightHeader = { type = "header", name = L["Assist Highlight"] or "보조 강조 효과", order = 20 },
        assistHighlightEnabled = GS_Toggle(groupName, "assistHighlightEnabled", L["Enable Assist Highlight"] or "보조 강조 효과 활성화", 20.1, false),
        assistHighlightType = GS_Select(groupName, "assistHighlightType", L["Highlight Type"] or "강조 유형", 20.2, "flipbook", {
            ["flipbook"] = L["Flipbook (Blizzard)"] or "Flipbook (Blizzard)",
            ["lcg"] = L["LibCustomGlow"] or "LibCustomGlow",
        }),
        assistFlipbookScale = GS_Range(groupName, "assistFlipbookScale", L["Flipbook Scale"] or "Flipbook 크기", 20.3, 1.5, 1.0, 2.5, 0.1),
        assistGlowType = GS_Select(groupName, "assistGlowType", L["Glow Type"] or "글로우 유형", 20.4, "Pixel Glow", {
            ["Pixel Glow"] = "Pixel Glow",
            ["Autocast Shine"] = "Autocast Shine",
            ["Action Button Glow"] = "Action Button Glow",
            ["Proc Glow"] = "Proc Glow",
            ["Blizzard Glow"] = "Blizzard Glow",
        }),
        assistGlowColor = GS_Color(groupName, "assistGlowColor", L["Assist Glow Color"] or "보조 강조 색상", 20.5, {0.3, 0.7, 1.0, 1}),
        assistGlowLines = GS_Range(groupName, "assistGlowLines", L["Pixel Glow Lines"] or "라인 수", 20.6, 10, 1, 30, 1),
        assistGlowFrequency = GS_Range(groupName, "assistGlowFrequency", L["Pixel Glow Speed"] or "속도", 20.7, 0.25, 0.01, 1.0, 0.01),
        assistGlowThickness = GS_Range(groupName, "assistGlowThickness", L["Pixel Glow Thickness"] or "두께", 20.8, 1, 0.5, 5, 0.5),
        assistHighlightPixelLength = GS_Range(groupName, "assistHighlightPixelLength", L["Pixel Glow Length"] or "길이", 20.9, 8, 1, 10, 1),
        -- 이동 애니메이션
        motionHeader = isBuffGroup and { type = "header", name = L["Movement Animation"] or "이동 애니메이션", order = 24 } or nil,
        iconMotion = isBuffGroup and GS_Toggle(groupName, "iconMotion", L["Enable Movement Animation"] or "이동 애니메이션 사용", 24.1, true) or nil,
        iconMotionDuration = isBuffGroup and GS_Range(groupName, "iconMotionDuration", L["Motion Duration"] or "모션 시간", 24.2, 0.18, 0.05, 0.5, 0.01, {
            disabled = function()
                local gs = GetGS()
                local g = gs and gs.groups[groupName]
                return g and g.iconMotion == false
            end,
        }) or nil,
        -- 애니메이션
        animHeader = { type = "header", name = L["Animation"] or "애니메이션", order = 25 },
        disableEdgeGlow = GS_Toggle(groupName, "disableEdgeGlow", L["Disable Edge Glow"] or "엣지 글로우 비활성화", 26, false),
        disableBlingAnimation = GS_Toggle(groupName, "disableBlingAnimation", L["Disable Bling Animation"] or "블링 애니메이션 비활성화", 27, false),
    }
end

local function GS_Font(groupName, key, name, order, default)
    return {
        type = "select", dialogControl = "LSM30_Font",
        name = name, order = order, width = "full",
        values = AceGUIWidgetLSMlists and AceGUIWidgetLSMlists.font or {},
        get = function()
            local gs = GetGS(); local g = gs and gs.groups[groupName]
            return g and g[key] or default
        end,
        set = function(_, val)
            local gs = GetGS()
            if gs and gs.groups[groupName] then gs.groups[groupName][key] = val; RefreshGroupSystem() end
        end,
    }
end

-- [CATEGORY] 커스텀 그룹용 텍스트 옵션 빌드 (카테고리별 분기)
local function BuildCustomTextArgs(groupName, category)
    local args = {
        -- 충전/스택 텍스트
        chargeTextHeader = { type = "header", name = L["Stack Text"] or "중첩 텍스트", order = 1 },
        countTextFont = GS_Font(groupName, "countTextFont", L["Font"] or "폰트", 1.5, "2002"),
        countTextSize = GS_Range(groupName, "countTextSize", L["Font Size"] or "글꼴 크기", 2, 14, 6, 32, 1),
        countTextColor = GS_Color(groupName, "countTextColor", L["Font Color"] or "글꼴 색상", 3, {1, 0.82, 0, 1}),
        countTextAnchor = GS_Select(groupName, "chargeTextAnchor", L["Anchor"] or "앵커", 4, "BOTTOMRIGHT", ANCHOR_POINTS),
        countTextOffsetX = GS_Range(groupName, "countTextOffsetX", L["X Offset"] or "X 오프셋", 5, 0, -20, 20, 1),
        countTextOffsetY = GS_Range(groupName, "countTextOffsetY", L["Y Offset"] or "Y 오프셋", 6, 0, -20, 20, 1),
        -- 쿨다운 텍스트
        cooldownTextHeader = { type = "header", name = L["Cooldown Text"] or "쿨다운 텍스트", order = 10 },
        cooldownFont = GS_Font(groupName, "cooldownFont", L["Font"] or "폰트", 10.5, "2002"),
        cooldownFontSize = GS_Range(groupName, "cooldownFontSize", L["Font Size"] or "글꼴 크기", 11, 14, 6, 32, 1),
        cooldownTextColor = GS_Color(groupName, "cooldownTextColor", L["Font Color"] or "글꼴 색상", 12, {1, 1, 1, 1}),
        cooldownTextAnchor = GS_Select(groupName, "cooldownTextAnchor", L["Anchor"] or "앵커", 13, "CENTER", ANCHOR_POINTS),
        cooldownTextOffsetX = GS_Range(groupName, "cooldownTextOffsetX", L["X Offset"] or "X 오프셋", 14, 0, -20, 20, 1),
        cooldownTextOffsetY = GS_Range(groupName, "cooldownTextOffsetY", L["Y Offset"] or "Y 오프셋", 15, 0, -20, 20, 1),
        -- [5TAB] 그림자는 시각 효과 탭으로 이동됨
    }

    -- 버프 카테고리: 지속시간 텍스트 추가
    if category == "buff" then
        args.durationHeader = { type = "header", name = L["Duration Text"] or "지속시간 텍스트", order = 30 }
        args.durationTextFont = GS_Font(groupName, "durationTextFont", L["Font"] or "폰트", 30.5, "2002")
        args.durationTextSize = GS_Range(groupName, "durationTextSize", L["Font Size"] or "글꼴 크기", 31, 12, 6, 32, 1)
        args.durationTextColor = GS_Color(groupName, "durationTextColor", L["Font Color"] or "글꼴 색상", 32, {1, 1, 1, 1})
        args.durationTextAnchor = GS_Select(groupName, "durationTextAnchor", L["Anchor"] or "앵커", 33, "TOP", ANCHOR_POINTS)
        args.durationTextOffsetX = GS_Range(groupName, "durationTextOffsetX", L["X Offset"] or "X 오프셋", 34, 0, -20, 20, 1)
        args.durationTextOffsetY = GS_Range(groupName, "durationTextOffsetY", L["Y Offset"] or "Y 오프셋", 35, 0, -20, 20, 1)
    end

    return args
end

local function CreateGroupOptions(groupName, order)
    local gs = GetGS()
    local groupSettings = gs and gs.groups and gs.groups[groupName]
    local isCDM = CDM_GROUPS[groupName]
    local displayName = GROUP_DISPLAY_NAMES[groupName]
        or (groupSettings and groupSettings.name)
        or groupName

    local viewerKey = GROUP_VIEWER_MAP[groupName]
    local category = GetGroupCategory(groupName)

    -- [Ayije 통합] CDM/커스텀 구분 없이 동일 옵션 빌더 사용

    local args = {}

    -- ========== 1. 배치 ==========
    local layoutArgs = {
        enabled = {
            type = "toggle",
            name = L["Enable"] or "활성화",
            order = 0, width = "full",
            get = function()
                local gs = GetGS()
                return gs and gs.groups[groupName] and gs.groups[groupName].enabled
            end,
            set = function(_, val)
                local gs = GetGS()
                if gs and gs.groups[groupName] then
                    local grp = gs.groups[groupName]
                    grp.enabled = val == true
                    if grp.groupType == "dynamic" and grp.sourceGroupKey then
                        local dynDB = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.dynamicIcons
                        local sourceGroup = dynDB and dynDB.groups and dynDB.groups[grp.sourceGroupKey]
                        if sourceGroup then
                            sourceGroup.enabled = grp.enabled
                        end
                    end
                    RefreshGroupSystem()
                    SoftRefreshGroupSystemOptions(0)
                end
            end,
        },
        -- [FIX] 그룹 분류 드롭다운 (다이나믹 그룹 전용)
        -- 카테고리에 따라 빠른 할당 카탈로그 필터링 + 아이템/장신구 버튼 표시 제어
        groupCategory = not isCDM and {
            type = "select",
            name = L["Group Category"] or "그룹 분류",
            desc = L["Select category used by spell and icon add controls"] or "스펠/아이콘 추가에서 사용할 분류를 선택합니다",
            order = 0.5, width = "full",
            values = CATEGORY_VALUES,
            get = function()
                local gs = GetGS(); local g = gs and gs.groups[groupName]
                return g and g.groupCategory or "skill"
            end,
            set = function(_, val)
                local gs = GetGS()
                if gs and gs.groups[groupName] then
                    gs.groups[groupName].groupCategory = val
                    RefreshGroupSystem()
                end
                -- 빠른 할당/텍스트 탭은 카테고리별로 옵션 구성이 달라져서 즉시 재빌드가 필요
                SoftRefreshGroupSystemOptions(0)
            end,
        } or nil,
        appearanceHeader = { type = "header", name = L["Appearance"] or "외관", order = 1 },
        iconSize = GS_Range(groupName, "iconSize", L["Icon Size"] or "아이콘 크기", 2, 32, 16, 80, 1),
        spacing = GS_Range(groupName, "spacing", L["Spacing"] or "간격", 3, 2, 0, 20, 1),
        borderSize = GS_Range(groupName, "borderSize", L["Border Size"] or "테두리 크기", 4, 1, 0, 5, 1),
        borderColor = GS_Color(groupName, "borderColor", L["Border Color"] or "테두리 색상", 5, {0,0,0,1}),
        zoom = GS_Range(groupName, "zoom", L["Zoom"] or "줌", 6, 0.08, 0, 0.3, 0.01, { isPercent = true }),
        aspectRatio = GS_Range(groupName, "aspectRatioCrop", L["Aspect Ratio"] or "종횡비", 7, 1.0, 0.5, 2.5, 0.01, -- [12.0.1]
            { desc = L["Control the icon aspect ratio. 1.0 = square, >1.0 = wider, <1.0 = taller"] or "아이콘 종횡비. 1.0=정사각형, >1.0=가로형, <1.0=세로형" }),
        groupAlpha = GS_Range(groupName, "groupAlpha", L["Opacity"] or "투명도", 8, 1.0, 0, 1.0, 0.05, { isPercent = true }),
        layoutHeader = { type = "header", name = L["Layout"] or "레이아웃", order = 10 },
        direction = GS_Select(groupName, "direction", L["Growth Direction"] or "성장 방향", 11, "RIGHT", DIRECTION_VALUES),
        growDirection = GS_Select(groupName, "growDirection", L["Wrap Direction"] or "줄바꿈 방향", 12, "DOWN", DIRECTION_VALUES),
        rowLimit = GS_Range(groupName, "rowLimit", L["Icons Per Row"] or "줄당 아이콘 수", 13, 8, 1, 20, 1),
        rowIconSize1 = {
            type = "range", name = L["Row 1 Icon Size"] or "1번 줄 아이콘 크기",
            desc = L["Override the icon size for the first row. Set to 0 to use the base Icon Size value."] or "1번 줄에만 적용될 아이콘 크기를 덮어씁니다. 0으로 설정하면 기본 아이콘 크기를 사용합니다.",
            order = 13.1, width = "normal", min = 0, max = 128, step = 1,
            get = function()
                local vn = GROUP_VIEWER_MAP[groupName]
                if vn then
                    local profile = DDingUI.db and DDingUI.db.profile
                    local vs = profile and profile.viewers and profile.viewers[vn]
                    return (vs and vs.rowIconSizes and vs.rowIconSizes[1]) or 0
                end
                local gs = GetGS(); local g = gs and gs.groups[groupName]
                return (g and g.rowIconSizes and g.rowIconSizes[1]) or 0
            end,
            set = function(_, val)
                local resolvedVal = (val and val > 0) and val or nil
                -- [FIX] 핵심 그룹 → 뷰어 설정에도 동기화
                local vn = GROUP_VIEWER_MAP[groupName]
                if vn then
                    local profile = DDingUI.db and DDingUI.db.profile
                    if profile then
                        profile.viewers = profile.viewers or {}
                        profile.viewers[vn] = profile.viewers[vn] or {}
                        profile.viewers[vn].rowIconSizes = profile.viewers[vn].rowIconSizes or {}
                        profile.viewers[vn].rowIconSizes[1] = resolvedVal
                    end
                end
                local gs = GetGS()
                if gs and gs.groups[groupName] then
                    gs.groups[groupName].rowIconSizes = gs.groups[groupName].rowIconSizes or {}
                    gs.groups[groupName].rowIconSizes[1] = resolvedVal
                    RefreshGroupLayout()
                    RefreshGroupSystem()
                end
            end,
        },
        rowIconSize2 = {
            type = "range", name = L["Row 2 Icon Size"] or "2번 줄 아이콘 크기",
            desc = L["Override the icon size for the second row. Set to 0 to use the base Icon Size value."] or "2번 줄에만 적용될 아이콘 크기를 덮어씁니다. 0으로 설정하면 기본 아이콘 크기를 사용합니다.",
            order = 13.2, width = "normal", min = 0, max = 128, step = 1,
            get = function()
                local vn = GROUP_VIEWER_MAP[groupName]
                if vn then
                    local profile = DDingUI.db and DDingUI.db.profile
                    local vs = profile and profile.viewers and profile.viewers[vn]
                    return (vs and vs.rowIconSizes and vs.rowIconSizes[2]) or 0
                end
                local gs = GetGS(); local g = gs and gs.groups[groupName]
                return (g and g.rowIconSizes and g.rowIconSizes[2]) or 0
            end,
            set = function(_, val)
                local resolvedVal = (val and val > 0) and val or nil
                local vn = GROUP_VIEWER_MAP[groupName]
                if vn then
                    local profile = DDingUI.db and DDingUI.db.profile
                    if profile then
                        profile.viewers = profile.viewers or {}
                        profile.viewers[vn] = profile.viewers[vn] or {}
                        profile.viewers[vn].rowIconSizes = profile.viewers[vn].rowIconSizes or {}
                        profile.viewers[vn].rowIconSizes[2] = resolvedVal
                    end
                end
                local gs = GetGS()
                if gs and gs.groups[groupName] then
                    gs.groups[groupName].rowIconSizes = gs.groups[groupName].rowIconSizes or {}
                    gs.groups[groupName].rowIconSizes[2] = resolvedVal
                    RefreshGroupLayout()
                    RefreshGroupSystem()
                end
            end,
        },
        rowIconSize3 = {
            type = "range", name = L["Row 3 Icon Size"] or "3번 줄 아이콘 크기",
            desc = L["Override the icon size for the third row. Set to 0 to use the base Icon Size value."] or "3번 줄에만 적용될 아이콘 크기를 덮어씁니다. 0으로 설정하면 기본 아이콘 크기를 사용합니다.",
            order = 13.3, width = "normal", min = 0, max = 128, step = 1,
            get = function()
                local vn = GROUP_VIEWER_MAP[groupName]
                if vn then
                    local profile = DDingUI.db and DDingUI.db.profile
                    local vs = profile and profile.viewers and profile.viewers[vn]
                    return (vs and vs.rowIconSizes and vs.rowIconSizes[3]) or 0
                end
                local gs = GetGS(); local g = gs and gs.groups[groupName]
                return (g and g.rowIconSizes and g.rowIconSizes[3]) or 0
            end,
            set = function(_, val)
                local resolvedVal = (val and val > 0) and val or nil
                local vn = GROUP_VIEWER_MAP[groupName]
                if vn then
                    local profile = DDingUI.db and DDingUI.db.profile
                    if profile then
                        profile.viewers = profile.viewers or {}
                        profile.viewers[vn] = profile.viewers[vn] or {}
                        profile.viewers[vn].rowIconSizes = profile.viewers[vn].rowIconSizes or {}
                        profile.viewers[vn].rowIconSizes[3] = resolvedVal
                    end
                end
                local gs = GetGS()
                if gs and gs.groups[groupName] then
                    gs.groups[groupName].rowIconSizes = gs.groups[groupName].rowIconSizes or {}
                    gs.groups[groupName].rowIconSizes[3] = resolvedVal
                    RefreshGroupLayout()
                    RefreshGroupSystem()
                end
            end,
        },
        -- [5TAB] 앵커 설정
        anchorSettingsHeader = { type = "header", name = L["Anchor Settings"] or "앵커 설정", order = 20 },
        selfPoint = {
            type = "select", name = L["Self Point"] or "기준점 (셀프 포인트)",
            order = 20.5, width = "full", values = ANCHOR_VALUES,
            get = function()
                local gs = GetGS(); local g = gs and gs.groups[groupName]
                return g and g.selfPoint or "CENTER"
            end,
            set = function(_, val)
                local gs = GetGS()
                if gs and gs.groups[groupName] then
                    gs.groups[groupName].selfPoint = val
                    RefreshGroupSystem()
                end
            end,
        },
        anchorPoint = {
            type = "select", name = L["Anchor Point"] or "앵커 포인트",
            order = 21, width = "full", values = ANCHOR_VALUES,
            get = function()
                local gs = GetGS(); local g = gs and gs.groups[groupName]
                return g and g.anchorPoint or "CENTER"
            end,
            set = function(_, val)
                local gs = GetGS()
                if gs and gs.groups[groupName] then
                    gs.groups[groupName].anchorPoint = val
                    RefreshGroupSystem()
                end
            end,
        },
        attachTo = {
            type = "select",
            name = L["Attach To"] or "연결 프레임",
            desc = L["Target frame name to attach this group (leave empty for UIParent)"] or "그룹을 연결할 프레임 이름 (비우면 UIParent)",
            order = 22, width = "full",
            values = function()
                local vals = { ["UIParent"] = "UIParent (화면)" }
                -- CDM 프록시 앵커
                vals["DDingUI_Anchor_Cooldowns"] = "CDM: 핵심 능력"
                vals["DDingUI_Anchor_Buffs"]     = "CDM: 강화 효과"
                vals["DDingUI_Anchor_Utility"]   = "CDM: 보조 능력"
                -- 다른 그룹
                local gs = GetGS()
                if gs and gs.groups then
                    for gn, g in pairs(gs.groups) do
                        if gn ~= groupName then
                            local dn = GROUP_DISPLAY_NAMES[gn] or g.name or gn
                            local frameName = "DDingUI_Group_" .. gn
                            vals[frameName] = "그룹: " .. dn
                        end
                    end
                end
                -- DDingUI_UF 프레임
                if DDingUI.UF_ANCHOR_FRAMES then
                    for _, uf in ipairs(DDingUI.UF_ANCHOR_FRAMES) do
                        vals[uf.name] = uf.display
                    end
                end
                return vals
            end,
            sorting = function()
                local order = { "UIParent",
                    "DDingUI_Anchor_Cooldowns", "DDingUI_Anchor_Buffs", "DDingUI_Anchor_Utility" }
                -- UF 프레임
                if DDingUI.UF_ANCHOR_FRAMES then
                    for _, uf in ipairs(DDingUI.UF_ANCHOR_FRAMES) do
                        order[#order + 1] = uf.name
                    end
                end
                -- 다른 그룹
                local gs = GetGS()
                if gs and gs.groups then
                    for gn in pairs(gs.groups) do
                        if gn ~= groupName then
                            order[#order + 1] = "DDingUI_Group_" .. gn
                        end
                    end
                end
                return order
            end,
            get = function()
                local gs = GetGS(); local g = gs and gs.groups[groupName]
                return g and g.attachTo or "UIParent"
            end,
            set = function(_, val)
                local gs = GetGS()
                if gs and gs.groups[groupName] then
                    gs.groups[groupName].attachTo = (val and val ~= "") and val or "UIParent"
                    RefreshGroupSystem()
                end
            end,
        },
        anchorPick = {
            type = "execute",
            name = L["Pick Frame (Mouse)"] or "프레임 선택 (마우스)",
            desc = L["Click a frame on screen to attach this group to it"] or "화면에서 프레임을 클릭하여 그룹을 고정합니다",
            order = 23, width = "full",
            func = function()
                if DDingUI.StartFramePicker then
                    DDingUI:StartFramePicker(function(frameName)
                        local gs = GetGS()
                        if gs and gs.groups[groupName] then
                            gs.groups[groupName].attachTo = frameName or "UIParent"
                            RefreshGroupSystem()
                            DDingUI:RefreshConfigGUI(false, "groupSystem.group_" .. groupName)
                        end
                    end)
                end
            end,
        },
        anchorClear = {
            type = "execute",
            name = L["Clear Anchor"] or "앵커 초기화",
            order = 24, width = "full",
            func = function()
                local gs = GetGS()
                if gs and gs.groups[groupName] then
                    gs.groups[groupName].attachTo = "UIParent"
                    gs.groups[groupName].anchorPoint = "CENTER"
                    gs.groups[groupName].selfPoint = "CENTER"
                    gs.groups[groupName].offsetX = 0
                    gs.groups[groupName].offsetY = 0
                    RefreshGroupSystem()
                    DDingUI:RefreshConfigGUI(false, "groupSystem.group_" .. groupName)
                end
            end,
        },
        offsetX = {
            type = "range", name = L["X Offset"] or "X 오프셋",
            order = 25, width = "full", min = -500, max = 500, step = 1,
            get = function()
                local gs = GetGS(); local g = gs and gs.groups[groupName]
                return g and g.offsetX or 0
            end,
            set = function(_, val)
                local gs = GetGS()
                if gs and gs.groups[groupName] then
                    gs.groups[groupName].offsetX = val
                    RefreshGroupSystem()
                end
            end,
        },
        offsetY = {
            type = "range", name = L["Y Offset"] or "Y 오프셋",
            order = 26, width = "full", min = -500, max = 500, step = 1,
            get = function()
                local gs = GetGS(); local g = gs and gs.groups[groupName]
                return g and g.offsetY or 0
            end,
            set = function(_, val)
                local gs = GetGS()
                if gs and gs.groups[groupName] then
                    gs.groups[groupName].offsetY = val
                    RefreshGroupSystem()
                end
            end,
        },
        anchorNote = {
            type = "description", order = 27,
            name = "|cff888888" .. (L["Tip: Use Edit Mode (Esc > Edit Mode) to drag groups directly."] or "팁: 편집 모드(Esc → 편집 모드)에서 그룹을 직접 드래그할 수 있습니다.") .. "|r",
        },
    }

    -- 커스텀 그룹: 삭제 버튼
    if not isCDM then
        layoutArgs.deleteHeader = { type = "header", name = L["Delete Group"] or "그룹 삭제", order = 90 }
        layoutArgs.deleteGroup = {
            type = "execute", name = L["Delete Group"] or "그룹 삭제",
            order = 91, width = "full",
            func = function()
                local dialog = StaticPopup_Show("DDINGUI_DELETE_GROUP", displayName)
                if dialog then
                    dialog.data = {
                        onAccept = function()
                            if DDingUI.GroupManager then
                                -- [FIX] 다이나믹 그룹이면 CustomIcons 원본도 같이 삭제 (고스트 프레임 방지)
                                local gsCheck = GetGS()
                                local grpInfo = gsCheck and gsCheck.groups and gsCheck.groups[groupName]
                                local capturedSourceKey = grpInfo and grpInfo.sourceGroupKey
                                if grpInfo and grpInfo.groupType == "dynamic" and capturedSourceKey then
                                    local ci = DDingUI.CustomIcons
                                    if ci and ci.RemoveGroup then
                                        ci:RemoveGroup(capturedSourceKey)
                                    end
                                    -- [FIX] 네이티브 컨테이너 즉시 숨기기
                                    if ci and ci.GetGroupFrames then
                                        local gFrames = ci:GetGroupFrames()
                                        if gFrames and gFrames[capturedSourceKey] then
                                            local cont = gFrames[capturedSourceKey]
                                            for _, child in ipairs({ cont:GetChildren() }) do child:Hide() end
                                            cont:Hide()
                                        end
                                    end
                                end
                                DDingUI.GroupManager:DeleteGroup(groupName)
                                -- [FIX] sourceGroupKey를 전달 (DeleteGroup이 DB에서 이미 삭제했으므로)
                                if DDingUI.GroupSystem then DDingUI.GroupSystem:OnGroupDeleted(groupName, capturedSourceKey) end
                                -- [12.0.1] 트리 메뉴 전체 재빌드 → 삭제된 그룹 즉시 반영
                                DDingUI:RefreshConfigGUI(false, "groupSystem")
                            end
                        end,
                    }
                end
            end,
        }
    end
    layoutArgs.assignedHeader = {
        type = "header",
        name = L["Assigned Spells"] or "할당된 스펠",
        order = -30,
    }
    layoutArgs.restoreBlizzardOrder = isCDM and {
        type = "execute",
        name = L["Restore Blizzard CDM Order"] or "블리자드 CDM 기본 순서로 복원",
        desc = L["Clear the manual icon order for this group and fall back to Blizzard's current CDM order."] or "이 그룹의 수동 아이콘 순서를 지우고 현재 블리자드 CDM 기본 순서로 되돌립니다.",
        order = -29,
        width = "normal",
        disabled = function()
            local gsNow = GetGS()
            local iconOrder = gsNow and gsNow.groups and gsNow.groups[groupName] and gsNow.groups[groupName].iconOrder
            return type(iconOrder) ~= "table" or next(iconOrder) == nil
        end,
        func = function()
            if DDingUI.ResetGroupSystemIconOrder and DDingUI:ResetGroupSystemIconOrder(groupName) then
                SoftRefreshGroupSystemOptions(0)
            end
        end,
    } or nil
    layoutArgs.assignedIconGrid = {
        type = "groupAssignedIconGrid",
        groupName = groupName,
        order = -28,
        width = "full",
    }

    args.layout = {
        type = "group",
        name = L["Layout"] or "배치",
        order = 10,
        args = layoutArgs,
    }

    -- ========== 2. 스펠 관리 ==========
    -- [FIX] CDM 기본 그룹에서도 아이템/장신구/종족특성 프리셋 표시
    -- 이전: (not isCDM) and (category ~= "buff") → CDM 그룹에서 모든 프리셋 숨김
    -- 현재: buff 카테고리만 제외 (CDM Buffs 그룹은 버프 전용이므로 아이템 추가 불필요)
    local showInlineAddOptions = false
    local showAdvanced = showInlineAddOptions and (category ~= "buff")
    args.spellManagement = {
        type = "group",
        name = L["Spell Management"] or "스펠 관리",
        order = 20,
        args = {
            assignedHeader = { type = "header", name = L["Assigned Spells"] or "할당된 스펠", order = 10 },
            restoreBlizzardOrder = isCDM and {
                type = "execute",
                name = L["Restore Blizzard CDM Order"] or "블리자드 CDM 기본 순서로 복원",
                desc = L["Clear the manual icon order for this group and fall back to Blizzard's current CDM order."] or "이 그룹의 수동 아이콘 순서를 지우고 현재 블리자드 CDM 기본 순서로 되돌립니다.",
                order = 12,
                width = "normal",
                disabled = function()
                    local gsNow = GetGS()
                    local iconOrder = gsNow and gsNow.groups and gsNow.groups[groupName] and gsNow.groups[groupName].iconOrder
                    return type(iconOrder) ~= "table" or next(iconOrder) == nil
                end,
                func = function()
                    if DDingUI.ResetGroupSystemIconOrder and DDingUI:ResetGroupSystemIconOrder(groupName) then
                        SoftRefreshGroupSystemOptions(0)
                    end
                end,
            } or nil,
            addSpellHeader = GROUP_SPELL_INPUT_ENABLED and { type = "header", name = L["Add Spell"] or "스펠 추가", order = 20 } or nil,
            addSpell = GROUP_SPELL_INPUT_ENABLED and {
                type = "spellSearch", -- [REFACTOR] Ayije 패턴 이식 — 실시간 Spell ID 검증
                name = L["Spell Name or ID"] or "스펠 이름 또는 ID",
                placeholder = "Spell ID...",
                buttonText = "추가",
                order = 21, width = "full",
                onAdd = function(val)
                    if isCDM then
                        -- CDM 그룹: spellAssignments 경로
                        local spellName = ResolveSpellInput(val, groupName)
                        if spellName and DDingUI.GroupManager and DDingUI.GroupManager:AssignSpell(spellName, groupName) then
                            SoftRefreshDynamicIcons()
                            return true
                        end
                        return false
                    else
                        -- 동적 그룹: CustomIcons 경로 (아이템과 같은 배열 → 드래그 순서 변경 가능)
                        local spellID = tonumber(val)
                        if not spellID then
                            -- 이름으로 입력한 경우 → ID 변환
                            if C_Spell and C_Spell.GetSpellInfo then
                                local info = C_Spell.GetSpellInfo(val)
                                spellID = info and info.spellID
                            end
                        end
                        if not spellID or spellID <= 0 then
                            UIErrorsFrame:AddMessage(L["Invalid Spell"] or "잘못된 스펠", 1, 0, 0)
                            return false
                        end
                        local ci = DDingUI.CustomIcons
                        if ci and ci.AddDynamicIcon then
                            -- [FIX] buff_ 접두사 처리: 버프 뷰어 그룹이면 aura 타입 (커스텀 그룹 호환)
                            local isBuffGrp = false
                            local targetViewer = GROUP_VIEWER_MAP[groupName]
                            if targetViewer then
                                isBuffGrp = (targetViewer == "BuffIconCooldownViewer")
                            else
                                local category = GetGroupCategory(groupName)
                                isBuffGrp = (category == "buff")
                            end
                            local iconType = isBuffGrp and "aura" or "spell"
                            
                            local iconKey = AddOrReuseDynamicSpellIcon(groupName, iconType, spellID, tostring(val))
                            if not iconKey then return false end
                            -- 프레임 생성 완료까지 폴링 후 갱신
                            local attempts = 0
                            local poller = nil
                            poller = C_Timer.NewTicker(0.5, function()
                                attempts = attempts + 1
                                local hasFrame = ci.GetAllIconFrames and ci:GetAllIconFrames()[iconKey]
                                if hasFrame or attempts >= 6 then
                                    if poller then poller:Cancel() end
                                    SoftRefreshDynamicIcons()
                                end
                            end)
                            return true
                        end
                        return false
                    end
                end,
            } or nil,

            -- ===========================================
            -- [QUICK-ADD] 커스텀 강화효과 빠른 추가 (버프 그룹 전용)
            -- [FIX] CDM 기본그룹은 AssignSpell 경로, 커스텀 그룹은 CustomIcons 경로
            -- ===========================================
            customBuffHeader = (showInlineAddOptions and category == "buff") and {
                type = "header", name = "커스텀 강화효과 빠른 추가", order = 25,
            } or nil,

            addLightsPotential = (showInlineAddOptions and category == "buff") and {
                type = "execute", order = 25.1, width = "normal",
                name = function()
                    local ok, tex = pcall(function() return C_Spell.GetSpellTexture(1236616) end)
                    local icon = (ok and tex and tex ~= 0) and tex or 134830
                    return "|T" .. icon .. ":16:16:0:0|t 빛의 잠재력"
                end,
                desc = "Spell ID: 1236616\n빛의 잠재력 (연금술 물약 강화 효과)을 추적합니다.",
                func = function()
                    if not DDingUI.CustomIcons then return end
                    local sourceKey = EnsureSourceGroup(groupName)
                    local iconKey = DDingUI.CustomIcons:AddDynamicIcon({type = "aura", id = 1236616, settings = { customAuraDuration = 30, customAuraTrigger = "spellcast" }})
                    if iconKey and sourceKey then DDingUI.CustomIcons:MoveIconToGroup(iconKey, sourceKey) end
                    SoftRefreshDynamicIcons()
                end,
            } or nil,

            addRecklessness = (showInlineAddOptions and category == "buff") and {
                type = "execute", order = 25.2, width = "normal",
                name = function()
                    local ok, tex = pcall(function() return C_Spell.GetSpellTexture(1236994) end)
                    local icon = (ok and tex and tex ~= 0) and tex or 134830
                    return "|T" .. icon .. ":16:16:0:0|t 무모함의 물약"
                end,
                desc = "Spell ID: 1236994\n무모함의 물약 강화 효과를 추적합니다.",
                func = function()
                    if not DDingUI.CustomIcons then return end
                    local sourceKey = EnsureSourceGroup(groupName)
                    local iconKey = DDingUI.CustomIcons:AddDynamicIcon({type = "aura", id = 1236994, settings = { customAuraDuration = 30, customAuraTrigger = "spellcast" }})
                    if iconKey and sourceKey then DDingUI.CustomIcons:MoveIconToGroup(iconKey, sourceKey) end
                    SoftRefreshDynamicIcons()
                end,
            } or nil,

            addDevouredDreams = (showInlineAddOptions and category == "buff") and {
                type = "execute", order = 25.3, width = "normal",
                name = function()
                    local ok, tex = pcall(function() return C_Spell.GetSpellTexture(1239479) end)
                    local icon = (ok and tex and tex ~= 0) and tex or 134830
                    return "|T" .. icon .. ":16:16:0:0|t 삼켜진 꿈의 물약"
                end,
                desc = "Spell ID: 1239479\n삼켜진 꿈의 물약 강화 효과를 추적합니다.",
                func = function()
                    if not DDingUI.CustomIcons then return end
                    local sourceKey = EnsureSourceGroup(groupName)
                    local iconKey = DDingUI.CustomIcons:AddDynamicIcon({type = "aura", id = 1239479, settings = { customAuraDuration = 10, customAuraTrigger = "spellcast" }})
                    if iconKey and sourceKey then DDingUI.CustomIcons:MoveIconToGroup(iconKey, sourceKey) end
                    SoftRefreshDynamicIcons()
                end,
            } or nil,

            addTimeSpiral = (showInlineAddOptions and category == "buff") and {
                type = "execute", order = 25.4, width = "normal",
                name = function()
                    local ok, tex = pcall(function() return C_Spell.GetSpellTexture(374968) end)
                    local icon = (ok and tex and tex ~= 0) and tex or 134830
                    return "|T" .. icon .. ":16:16:0:0|t 시간의 와류"
                end,
                desc = "Spell ID: 374968\n시간의 와류 강화 효과를 추적합니다.",
                func = function()
                    if not DDingUI.CustomIcons then return end
                    local sourceKey = EnsureSourceGroup(groupName)
                    local iconKey = DDingUI.CustomIcons:AddDynamicIcon({type = "aura", id = 374968, settings = { customAuraDuration = 10, customAuraTrigger = "timespiral" }})
                    if iconKey and sourceKey then DDingUI.CustomIcons:MoveIconToGroup(iconKey, sourceKey) end
                    SoftRefreshDynamicIcons()
                end,
            } or nil,

            addBloodlust = (showInlineAddOptions and category == "buff") and {
                type = "execute", order = 25.5, width = "normal",
                name = function()
                    local ok, tex = pcall(function() return C_Spell.GetSpellTexture(2825) end)
                    local icon = (ok and tex and tex ~= 0) and tex or 134830
                    return "|T" .. icon .. ":16:16:0:0|t 피의 욕망 / 영웅심"
                end,
                desc = "Spell ID: 2825, 32182 등\n피의 욕망, 영웅심, 시간 왜곡 등 블러드류 버프를 추적합니다.",
                func = function()
                    if not DDingUI.CustomIcons then return end
                    local sourceKey = EnsureSourceGroup(groupName)
                    local iconKey = DDingUI.CustomIcons:AddDynamicIcon({type = "aura", id = 2825, settings = {
                        customAuraDuration = 40,
                        customAuraTrigger = "bloodlust",
                        auraAliases = {2825, 32182, 80353, 90355, 160452, 264667, 390386},
                    }})
                    if iconKey then
                        local db = DDingUI.db.profile.dynamicIcons
                        if db and db.iconData and db.iconData[iconKey] then
                            db.iconData[iconKey].settings = db.iconData[iconKey].settings or {}
                            db.iconData[iconKey].settings.auraAliases = {2825, 32182, 80353, 90355, 160452, 264667, 390386}
                        end
                        if sourceKey then DDingUI.CustomIcons:MoveIconToGroup(iconKey, sourceKey) end
                    end
                    SoftRefreshDynamicIcons()
                end,
            } or nil,

            iconGridHeader = GROUP_QUICK_ASSIGN_ENABLED and { type = "header", name = L["Quick Assign"] or "빠른 할당", order = 30 } or nil,
            iconGrid = GROUP_QUICK_ASSIGN_ENABLED and {
                type = "groupAssignGrid",
                name = L["Icon Assignment"] or "아이콘 할당",
                order = 31,
                groupName = groupName,
            } or nil,
            -- [12.0.1] 추가 옵션: 아이템/장신구 추가 (커스텀/동적 그룹 전용 + skill 카테고리만)
            advancedHeader = showAdvanced and { type = "header", name = L["Advanced Add"] or "추가 옵션 (아이템/장신구)", order = 40 } or nil,
            addItemID = showAdvanced and {
                type = "spellSearch",
                searchMode = "item", -- [FIX] 아이템 ID 프리뷰 (C_Item.GetItemInfo 사용)
                name = L["Item ID"] or "아이템 ID",
                placeholder = "Item ID...",
                buttonText = L["Add"] or "추가",
                order = 41, width = "full",
                onAdd = function(val)
                    local itemID = tonumber(val)
                    if not itemID or itemID <= 0 then
                        UIErrorsFrame:AddMessage(L["Invalid Item ID"] or "잘못된 아이템 ID", 1, 0, 0)
                        return false
                    end
                    -- [FIX] 아이템 데이터 프리로드 후 추가 (비동기 캐시 미스 방지)
                    C_Item.RequestLoadItemDataByID(itemID)
                    C_Timer.After(0.3, function()
                        if not DDingUI.CustomIcons then return end
                        local sourceKey = EnsureSourceGroup(groupName)
                        local iconKey = DDingUI.CustomIcons:AddDynamicIcon({type = "item", id = itemID})
                        if iconKey and sourceKey then
                            DDingUI.CustomIcons:MoveIconToGroup(iconKey, sourceKey)
                        end
                        -- 프레임 생성 완료까지 폴링 후 GroupSystem 갱신
                        local attempts = 0
                        local poller = nil
                        poller = C_Timer.NewTicker(0.5, function()
                            attempts = attempts + 1
                            local ci = DDingUI.CustomIcons
                            local hasFrame = ci and ci.GetAllIconFrames and ci:GetAllIconFrames()[iconKey]
                            if hasFrame or attempts >= 6 then
                                if poller then poller:Cancel() end
                                SoftRefreshDynamicIcons()
                            end
                        end)
                    end)
                    return true
                end,
            } or nil,
            addTrinket1 = showAdvanced and {
                type = "execute",
                name = L["Add Trinket 1 (Slot 13)"] or "장신구 1 추가 (슬롯 13)",
                desc = L["Automatically track trinket in slot 13 (proc detection + item cooldown)"] or "슬롯 13 장신구 자동 추적 (발동 감지 + 아이템 쿨다운)",
                order = 42, width = "normal",
                func = function()
                    if not DDingUI.CustomIcons then return end
                    local sourceKey = EnsureSourceGroup(groupName)
                    local iconKey = DDingUI.CustomIcons:AddDynamicIcon({type = "trinketProc", slotID = 13})
                    if iconKey and sourceKey then
                        DDingUI.CustomIcons:MoveIconToGroup(iconKey, sourceKey)
                    end
                    -- [FIX] 프레임 생성 완료까지 폴링 후 GroupSystem 갱신
                    local attempts = 0
                    local poller = nil
                    poller = C_Timer.NewTicker(0.5, function()
                        attempts = attempts + 1
                        local ci = DDingUI.CustomIcons
                        local hasFrame = ci and ci.GetAllIconFrames and ci:GetAllIconFrames()[iconKey]
                        if hasFrame or attempts >= 6 then
                            if poller then poller:Cancel() end
                            SoftRefreshDynamicIcons()
                        end
                    end)
                end,
            } or nil,
            addTrinket2 = showAdvanced and {
                type = "execute",
                name = L["Add Trinket 2 (Slot 14)"] or "장신구 2 추가 (슬롯 14)",
                desc = L["Automatically track trinket in slot 14 (proc detection + item cooldown)"] or "슬롯 14 장신구 자동 추적 (발동 감지 + 아이템 쿨다운)",
                order = 43, width = "normal",
                func = function()
                    if not DDingUI.CustomIcons then return end
                    local sourceKey = EnsureSourceGroup(groupName)
                    local iconKey = DDingUI.CustomIcons:AddDynamicIcon({type = "trinketProc", slotID = 14})
                    if iconKey and sourceKey then
                        DDingUI.CustomIcons:MoveIconToGroup(iconKey, sourceKey)
                    end
                    -- [FIX] 프레임 생성 완료까지 폴링 후 GroupSystem 갱신
                    local attempts = 0
                    local poller = nil
                    poller = C_Timer.NewTicker(0.5, function()
                        attempts = attempts + 1
                        local ci = DDingUI.CustomIcons
                        local hasFrame = ci and ci.GetAllIconFrames and ci:GetAllIconFrames()[iconKey]
                        if hasFrame or attempts >= 6 then
                            if poller then poller:Cancel() end
                            SoftRefreshDynamicIcons()
                        end
                    end)
                end,
            } or nil,
            advancedDesc = showAdvanced and {
                type = "description", order = 44,
                name = "|cff888888" .. (L["Trinkets auto-detect proc buffs and show item cooldown. Fallback items can be configured per-icon in Dynamic Icons tab."] or "장신구는 발동 버프를 자동 감지하고 아이템 쿨다운을 표시합니다. 폴백 아이템은 동적 아이콘 탭에서 아이콘별로 설정 가능합니다.") .. "|r",
            } or nil,

            -- ===========================================
            -- [QUICK-ADD] 소모품 + 종족 특성 빠른 추가
            -- ===========================================
            quickAddHeader = showAdvanced and {
                type = "header", name = L["Quick Add Consumables"] or "소모품 빠른 추가", order = 50,
            } or nil,

            -- 실버문 생명력 물약 (R2 241304 / R1 241305) — 항상 R2로 추가, 아이콘 표시 시 R1 폴백
            addHealthPotion = showAdvanced and {
                type = "execute", order = 51, width = "normal",
                name = function() local icon = C_Item.GetItemIconByID(241304) or 134830; return "|T" .. icon .. ":16:16:0:0|t " .. (L["Silvermoon Health Potion"] or "실버문 생명력 물약") end,
                desc = "Item ID: 241304 (★★) / 241305 (★)\n2성 미소지 시 1성 아이콘으로 자동 폴백합니다.",
                func = function()
                    if not DDingUI.CustomIcons then return end
                    local itemID = 241304  -- 항상 R2로 추가
                    C_Item.RequestLoadItemDataByID(itemID)
                    C_Item.RequestLoadItemDataByID(241305) -- R1 프리로드
                    C_Timer.After(0.3, function()
                        local sourceKey = EnsureSourceGroup(groupName)
                        local iconKey = DDingUI.CustomIcons:AddDynamicIcon({type = "item", id = itemID})
                        if iconKey then
                            -- R1 폴백 설정
                            local db = DDingUI.db.profile.dynamicIcons
                            if db and db.iconData and db.iconData[iconKey] then
                                db.iconData[iconKey].settings = db.iconData[iconKey].settings or {}
                                db.iconData[iconKey].settings.fallbackItems = "241305"
                            end
                            if sourceKey then DDingUI.CustomIcons:MoveIconToGroup(iconKey, sourceKey) end
                        end
                        SoftRefreshDynamicIcons()
                    end)
                end,
            } or nil,

            -- 빛주입 마나 물약 (R2 241300 / R1 241301) — 항상 R2로 추가, 아이콘 표시 시 R1 폴백
            addManaPotion = showAdvanced and {
                type = "execute", order = 52, width = "normal",
                name = function() local icon = C_Item.GetItemIconByID(241300) or 134830; return "|T" .. icon .. ":16:16:0:0|t " .. (L["Lightfused Mana Potion"] or "빛주입 마나 물약") end,
                desc = "Item ID: 241300 (★★) / 241301 (★)\n2성 미소지 시 1성 아이콘으로 자동 폴백합니다.",
                func = function()
                    if not DDingUI.CustomIcons then return end
                    local itemID = 241300
                    C_Item.RequestLoadItemDataByID(itemID)
                    C_Item.RequestLoadItemDataByID(241301)
                    C_Timer.After(0.3, function()
                        local sourceKey = EnsureSourceGroup(groupName)
                        local iconKey = DDingUI.CustomIcons:AddDynamicIcon({type = "item", id = itemID})
                        if iconKey then
                            local db = DDingUI.db.profile.dynamicIcons
                            if db and db.iconData and db.iconData[iconKey] then
                                db.iconData[iconKey].settings = db.iconData[iconKey].settings or {}
                                db.iconData[iconKey].settings.fallbackItems = "245917,245916,241301"
                            end
                            if sourceKey then DDingUI.CustomIcons:MoveIconToGroup(iconKey, sourceKey) end
                        end
                        SoftRefreshDynamicIcons()
                    end)
                end,
            } or nil,

            -- 빛의 잠재력 (R2 241308 / R1 241309) — 항상 R2로 추가, 아이콘 표시 시 R1 폴백
            addTemperedPotion = showAdvanced and {
                type = "execute", order = 53, width = "normal",
                name = function() local icon = C_Item.GetItemIconByID(241308) or 134830; return "|T" .. icon .. ":16:16:0:0|t " .. (L["Light's Potential"] or "빛의 잠재력") end,
                desc = "Item ID: 241308 (★★) / 241309 (★)\n2성 미소지 시 1성 아이콘으로 자동 폴백합니다.",
                func = function()
                    if not DDingUI.CustomIcons then return end
                    local itemID = 241308
                    C_Item.RequestLoadItemDataByID(itemID)
                    C_Item.RequestLoadItemDataByID(241309)
                    C_Timer.After(0.3, function()
                        local sourceKey = EnsureSourceGroup(groupName)
                        local iconKey = DDingUI.CustomIcons:AddDynamicIcon({type = "item", id = itemID})
                        if iconKey then
                            local db = DDingUI.db.profile.dynamicIcons
                            if db and db.iconData and db.iconData[iconKey] then
                                db.iconData[iconKey].settings = db.iconData[iconKey].settings or {}
                                db.iconData[iconKey].settings.fallbackItems = "245898,245897,241309"
                            end
                            if sourceKey then DDingUI.CustomIcons:MoveIconToGroup(iconKey, sourceKey) end
                        end
                        SoftRefreshDynamicIcons()
                    end)
                end,
            } or nil,

            -- 생명석 (아이템 5512 / 흑마법사 스펠 224464)
            addHealthstone = showAdvanced and {
                type = "execute", order = 54, width = "normal",
                name = function() local _, cls = UnitClass("player"); local icon = (cls == "WARLOCK") and (C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(224464) or 538745) or (C_Item.GetItemIconByID(5512) or 538745); return "|T" .. icon .. ":16:16:0:0|t " .. (L["Add Healthstone"] or "생명석 추가") end,
                desc = L["Add Healthstone icon. Warlocks use Create Healthstone spell, others use Healthstone item."] or "생명석 아이콘을 추가합니다. 흑마법사는 생명석 생성 스펠, 다른 직업은 생명석 아이템으로 추가됩니다.",
                func = function()
                    if not DDingUI.CustomIcons then return end
                    local sourceKey = EnsureSourceGroup(groupName)
                    local _, playerClass = UnitClass("player")
                    local iconKey
                    if playerClass == "WARLOCK" then
                        iconKey = DDingUI.CustomIcons:AddDynamicIcon({type = "item", id = 224464})
                    else
                        iconKey = DDingUI.CustomIcons:AddDynamicIcon({type = "item", id = 5512})
                    end
                    if iconKey and sourceKey then DDingUI.CustomIcons:MoveIconToGroup(iconKey, sourceKey) end
                    SoftRefreshDynamicIcons()
                end,
            } or nil,

            -- 종족 특성 (현재 캐릭터 종족 자동 감지)
            racialHeader = showAdvanced and {
                type = "header", name = L["Racial Ability"] or "종족 특성", order = 60,
            } or nil,
            addRacial = showAdvanced and {
                type = "execute", order = 61, width = "normal",
                name = function()
                    local RACIAL_SPELLS = {
                        Human       = 59752,
                        Orc         = 20572,
                        NightElf    = 58984,
                        Dwarf       = 20594,
                        Undead      = 7744,
                        Troll       = 26297,
                        BloodElf    = 25046,
                        Gnome       = 20589,
                        Draenei     = 28880,
                        Worgen      = 68992,
                        Goblin      = 69070,
                        Pandaren    = 107079,
                        VoidElf     = 256948,
                        LightforgedDraenei = 255647,
                        DarkIronDwarf  = 265221,
                        KulTiran    = 287712,
                        Mechagnome  = 312924,
                        Nightborne  = 260364,
                        HighmountainTauren = 255654,
                        MagharOrc   = 274738,
                        ZandalariTroll = 291944,
                        Vulpera     = 312411,
                        Dracthyr    = 368970,
                    }
                    local _, raceKey = UnitRace("player")
                    local raceFile = (raceKey or ""):gsub("%s", ""):gsub("^%l", string.upper)
                    local spellID = RACIAL_SPELLS[raceFile]
                    if spellID then
                        local spellName = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
                        if spellName then
                            return (L["Add Racial"] or "종족 특성 추가") .. ": " .. spellName
                        end
                    end
                    return L["Add Racial"] or "종족 특성 추가"
                end,
                desc = "현재 캐릭터의 종족 특성을 동적으로 표시하는 슬롯을 추가합니다. 프로필을 공유해도 접속한 캐릭터의 최신 종족 스킬이 자동 변환되어 적용됩니다.",
                func = function()
                    if not DDingUI.CustomIcons then return end
                    local sourceKey = EnsureSourceGroup(groupName)
                    -- 고정된 스펠 ID를 저장하지 않고, 렌더링 시점에 종족을 감지하는 메타 슬롯(racial)을 주입합니다
                    local iconKey = DDingUI.CustomIcons:AddDynamicIcon({type = "racial", id = "racial"})
                    if iconKey and sourceKey then DDingUI.CustomIcons:MoveIconToGroup(iconKey, sourceKey) end
                    SoftRefreshDynamicIcons()
                end,
            } or nil,
        },
    }

    -- Spell management controls now live at the top of the layout tab.
    args.spellManagement = nil

    -- [Ayije 통합] 모든 그룹 동일 시각 효과 옵션 (CDM/커스텀 구분 없음)
    local visualArgs = BuildCustomVisualArgs(groupName)
    args.visual = {
        type = "group",
        name = L["Visual Effects"] or "시각 효과",
        order = 30,
        args = visualArgs,
    }

    -- [Ayije 통합] 모든 그룹 동일 텍스트 옵션 (CDM/커스텀 구분 없음, 카테고리별 분기)
    local textArgs = BuildCustomTextArgs(groupName, category)
    args.text = {
        type = "group",
        name = L["Text"] or "텍스트",
        order = 40,
        args = textArgs,
    }

    -- ========== 5. 뷰어 오프셋 (CDM 그룹 전용) ==========
    if isCDM and viewerKey and ns.CreateSingleViewerOptions then
        local vo = ns.CreateSingleViewerOptions(viewerKey, displayName, 1)
        if vo and vo.args then
            local viewerDetailArgs = {}
            viewerDetailArgs.sec02_offsetHeader = { type = "header", name = L["Group Offsets"] or "그룹 오프셋 (파티/레이드)", order = 1 }
            viewerDetailArgs.groupOffsetDesc = CopyVO(vo.args, "groupOffsetDesc", 2)
            viewerDetailArgs.partyOffsetX    = CopyVO(vo.args, "partyOffsetX", 3)
            viewerDetailArgs.partyOffsetY    = CopyVO(vo.args, "partyOffsetY", 4)
            viewerDetailArgs.raidOffsetX     = CopyVO(vo.args, "raidOffsetX", 5)
            viewerDetailArgs.raidOffsetY     = CopyVO(vo.args, "raidOffsetY", 6)

            args.viewer = {
                type = "group",
                name = L["Group Offsets"] or "오프셋",
                order = 50,
                args = viewerDetailArgs,
            }
        end
    end

    return {
        type = "group",
        name = displayName,
        order = order,
        childGroups = "tab",
        args = args,
    }
end

-- ============================================================
-- 전체 그룹 시스템 옵션 빌드
-- ============================================================

local function BuildGroupSystemOptions(order)
    -- [DYNAMIC] 빌드 시점에 동적 그룹 동기화 (CustomIcons 그룹 → GroupSystem 그룹)
    if DDingUI.GroupSystem and DDingUI.GroupSystem.SyncDynamicGroups then
        DDingUI.GroupSystem:SyncDynamicGroups()
    end

    local options = {
        type = "group",
        name = L["Icon Groups"] or "아이콘 그룹",
        order = order,
        childGroups = "tab",
        args = {
            -- ========== 시스템 설정 ==========
            systemSettings = {
                type = "group",
                name = L["Settings"] or "설정",
                order = 0,
                args = {
                    -- [DYNAMIC] 활성화 토글 제거 — 아이콘 그룹은 무조건 활성

                    hideDefaultViewers = {
                        type = "toggle",
                        name = L["Hide Default Viewers"] or "기본 뷰어 숨기기",
                        desc = L["Hide WoW default cooldown viewers when group system is active"] or "그룹 시스템 활성 시 WoW 기본 쿨다운 뷰어 숨기기",
                        order = 3,
                        width = "full",
                        get = function()
                            local gs = GetGS()
                            return gs and gs.hideDefaultViewers
                        end,
                        set = function(_, val)
                            local gs = GetGS()
                            if gs then
                                gs.hideDefaultViewers = val
                                if DDingUI.GroupSystem then
                                    DDingUI.GroupSystem:Toggle()
                                end
                            end
                        end,
                    },
                    -- 새 그룹 추가
                    addGroupHeader = {
                        type = "header",
                        name = L["Add Group"] or "그룹 추가",
                        order = 10,
                    },
                    newGroupName = {
                        type = "input",
                        name = L["New Group Name"] or "새 그룹 이름",
                        desc = (L["Enter group name and click Create"] or "그룹 이름을 입력 후 '생성' 버튼을 누르세요"),
                        order = 11,
                        width = "double",
                        get = function() return pendingGroupName or "" end,
                        set = function(_, val)
                            -- [12.0.1] 이름만 저장, 그룹 생성은 버튼에서 처리 (포커스 잃을 때 리프레시 방지)
                            pendingGroupName = (val and val ~= "") and val or nil
                        end,
                    },
                    createGroupBtn = {
                        type = "execute",
                        name = L["Create"] or "생성",
                        order = 12,
                        width = "half",
                        disabled = function() return not pendingGroupName or pendingGroupName == "" end,
                        func = function()
                            local val = pendingGroupName
                            pendingGroupName = nil
                            if val and val ~= "" and DDingUI.GroupManager then
                                local ok = DDingUI.GroupManager:CreateGroup(val)
                                if ok then
                                    if DDingUI.GroupSystem then
                                        DDingUI.GroupSystem:OnGroupAdded(val)
                                    end
                                    -- [12.0.1] 트리 메뉴 전체 재빌드 → 새 그룹 즉시 반영
                                    DDingUI:RefreshConfigGUI(false, "groupSystem.group_" .. val)
                                end
                            end
                        end,
                    },
                },
            },
        },
    }

    -- 그룹별 탭 생성
    local gs = GetGS()
    if gs and gs.groups then
        local sorted = {}
        for name, settings in pairs(gs.groups) do
            sorted[#sorted + 1] = { name = name, order = settings.order or 999 }
        end
        table.sort(sorted, function(a, b) return a.order < b.order end)

        for i, entry in ipairs(sorted) do
            options.args["group_" .. entry.name] = CreateGroupOptions(entry.name, i)
        end
    end

    return options
end

-- Export
ns.CreateGroupSystemOptions = BuildGroupSystemOptions
DDingUI._CreateGroupSystemOptions = BuildGroupSystemOptions
-- [REFACTOR] ShowGroupAssignDialog 제거 → DDingUI:BuildGroupAssignGridUI 사용
