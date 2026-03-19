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
    if DDingUI.GroupSystem and DDingUI.GroupSystem.Refresh then
        DDingUI.GroupSystem:Refresh()
    end
    -- [FIX] 설정 변경을 SpecProfiles 스냅샷에 반영
    -- 누락 시 캐릭 전환/리로드에서 LoadSpec이 스냅샷(구 값)으로 덮어씀
    if DDingUI.SpecProfiles and DDingUI.SpecProfiles.MarkDirty then
        DDingUI.SpecProfiles:MarkDirty()
    end
end

-- [FIX] 수동 생성 그룹에 아이템/장신구 추가 시 CustomIcons 그룹과 자동 연결
-- sourceGroupKey가 없는 dynamic 그룹에 CustomIcons 그룹을 자동 생성하여 연결
local function EnsureSourceGroup(groupName)
    local gs = GetGS()
    if not gs or not gs.groups or not gs.groups[groupName] then return nil end
    local grp = gs.groups[groupName]
    -- 이미 sourceGroupKey가 있으면 그대로 반환
    if grp.sourceGroupKey then return grp.sourceGroupKey end
    -- CustomIcons 그룹 자동 생성
    local ci = DDingUI.CustomIcons
    if not ci or not ci.CreateDynamicGroup then return nil end
    local sourceKey = ci:CreateDynamicGroup(grp.name or groupName)
    if sourceKey then
        grp.sourceGroupKey = sourceKey
        grp.groupType = "dynamic"
    end
    return sourceKey
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
local function SoftRefreshDynamicIcons()
    -- 게임 레이아웃 갱신
    if DDingUI.GroupSystem and DDingUI.GroupSystem.RefreshLayout then
        DDingUI.GroupSystem:RefreshLayout()
    end
    -- GUI 목록 갱신 (지연, SoftRefresh로 메뉴 닫히지 않음)
    C_Timer.After(0.1, function()
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
    end)
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

-- CDMHookEngine에서 전체 뷰어 아이콘 목록 수집
-- [FIX] CDMScanner는 BuffIcon/BuffBar만 스캔 → Essential/Utility 누락
-- CDMHookEngine은 3개 뷰어 모두 스캔하므로 그룹 할당 그리드에 적합
local function GetCDMIconEntries()
    local CDMHookEngine = DDingUI.CDMHookEngine
    if not CDMHookEngine then return {} end

    CDMHookEngine:RebuildMaps()
    local iconMap = CDMHookEngine:GetIconMap()
    local result = {}

    for cooldownID, icon in pairs(iconMap) do
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
        }
    end

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

-- [REFACTOR] 인라인 그리드 업데이트 (groupName 인자로 받음)
local function UpdateGroupAssignGrid(parent, groupName)
    if not parent or not parent._grids then return end

    local allEntries = GetCDMIconEntries()
    local gs = GetGS()
    local assignments = gs and gs.spellAssignments or {}

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
                local assigned = btn.spellName and assignments[btn.spellName]
                if assigned == groupName then
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
        table.insert(viewersToRender, { key = targetViewer, name = "" })
    else
        viewersToRender = QUICK_ASSIGN_CATEGORIES
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
                    local assigned = self.spellName and gsCurrent and gsCurrent.spellAssignments and gsCurrent.spellAssignments[self.spellName]
                    if assigned then
                        if assigned == groupName then
                            GameTooltip:AddLine(L["Assigned to this group"] or "이 그룹에 할당됨", 0.3, 1, 0.3)
                        else
                            GameTooltip:AddLine((L["Assigned to: "] or "할당: ") .. assigned, 1, 0.5, 0.3)
                        end
                    else
                        GameTooltip:AddLine(L["Auto (Default)"] or "자동 (기본)", 0.5, 0.5, 0.5)
                    end

                    GameTooltip:AddLine(" ")
                    local toggleText = rawget(L, "Click: Toggle Assignment") or "클릭: 할당 / 해제"
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
                        -- [FIX] 다이나믹 그룹: buff는 CDM이 추적 → AssignSpell만
                        -- spell(쿨다운)만 CustomIcons 아이콘 생성
                        local isBuff = self.spellName and self.spellName:match("^buff_")
                        if isBuff then
                            -- [FIX] 강화효과: CustomIcons aura 타입으로 독립 프레임 생성
                            -- CDM reparent가 아닌 C_UnitAuras 기반 자체 추적
                            local ci = DDingUI.CustomIcons
                            if ci and ci.AddDynamicIcon then
                                local spellID = self.entry and self.entry.spellID
                                if (not spellID or spellID == 0) and C_Spell and C_Spell.GetSpellInfo then
                                    local rawName = self.spellName:gsub("^buff_", "")
                                    local info = C_Spell.GetSpellInfo(rawName)
                                    spellID = info and info.spellID
                                end
                                if spellID and spellID > 0 then
                                    local sourceKey = EnsureSourceGroup(groupName)
                                    local iconKey = ci:AddDynamicIcon({type = "aura", id = spellID})
                                    if iconKey and sourceKey then
                                        ci:MoveIconToGroup(iconKey, sourceKey)
                                    end
                                    -- [FIX] AssignSpell 복원: 리로드 직후 CDM spellName 미준비 시
                                    -- ClassifyIcon 1순위(spellAssignments) 폴백으로 올바른 그룹 분류 보장
                                    -- 삭제 시 dyna_ func에서 spellAssignments도 동기 제거됨
                                    local GroupMgr = DDingUI.GroupManager
                                    if GroupMgr and self.spellName then
                                        GroupMgr:AssignSpell(self.spellName, groupName)
                                    end
                                    SoftRefreshDynamicIcons()
                                else
                                    print("|cffffffffDDing|r|cffffa300UI|r: |cffff0000 스펠 ID를 찾을 수 없습니다: " .. (self.spellName or "?") .. "|r")
                                end
                            end
                        else
                            -- 주문(쿨다운): CustomIcons 아이콘 생성 + AssignSpell
                            local ci = DDingUI.CustomIcons
                            if ci and ci.AddDynamicIcon then
                                local iconType = "spell"
                                local spellID = self.entry and self.entry.spellID
                                if (not spellID or spellID == 0) and C_Spell and C_Spell.GetSpellInfo then
                                    local rawName = self.spellName:gsub("^buff_", "")
                                    local info = C_Spell.GetSpellInfo(rawName)
                                    spellID = info and info.spellID
                                end
                                if spellID and spellID > 0 then
                                    local sourceKey = EnsureSourceGroup(groupName)
                                    local iconKey = ci:AddDynamicIcon({type = iconType, id = spellID})
                                    if iconKey and sourceKey then
                                        ci:MoveIconToGroup(iconKey, sourceKey)
                                    end
                                    local GroupMgr = DDingUI.GroupManager
                                    if GroupMgr and self.spellName then
                                        GroupMgr:AssignSpell(self.spellName, groupName)
                                    end
                                    SoftRefreshDynamicIcons()
                                else
                                    print("|cffffffffDDing|r|cffffa300UI|r: |cffff0000 스펠 ID를 찾을 수 없습니다: " .. (self.spellName or "?") .. "|r")
                                end
                            end
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
    local count = 0

    -- 1. CDM 스펠 할당 (gs.spellAssignments)
    -- [FIX] aura 동적 아이콘이 있으면 같은 buff의 CDM 항목 UI 스킵
    local auraSpellNames = {}
    local grpCfg = gs and gs.groups and gs.groups[groupName]
    local sourceKey = grpCfg and grpCfg.sourceGroupKey
    if sourceKey then
        local dynDB = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.dynamicIcons
        local dynGroup = dynDB and dynDB.groups and dynDB.groups[sourceKey]
        if dynGroup and dynGroup.icons then
            local iconDataDB = dynDB.iconData
            for _, iconKey in ipairs(dynGroup.icons) do
                local iconData = iconDataDB and iconDataDB[iconKey]
                if iconData and iconData.type == "aura" and iconData.id then
                    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(iconData.id)
                    if info and info.name then
                        auraSpellNames["buff_" .. info.name] = true
                    end
                end
            end
        end
    end
    if gs and gs.spellAssignments then
        local cdmHook = DDingUI.CDMHookEngine
        
        -- 알파벳 순서대로 정렬
        local sortedList = {}
        for spellName, grp in pairs(gs.spellAssignments) do
            if grp == groupName and not auraSpellNames[spellName] then
                table.insert(sortedList, spellName)
            end
        end
        table.sort(sortedList)

        for _, spellName in ipairs(sortedList) do
            count = count + 1
            local displayName = spellName:gsub("^buff_", "")
            local iconTex = 134400
                            if cdmHook then
                                local iconMap = cdmHook:GetIconMap()
                                for cdId, iconFrame in pairs(iconMap) do
                                    if cdmHook:GetSpellNameForID(cdId) == spellName then
                                        local ok, tex = pcall(function() return iconFrame.Icon and iconFrame.Icon:GetTexture() end)
                                        if ok and tex and not (issecretvalue and issecretvalue(tex)) and tex ~= 0 and tex ~= "" and type(tex) == "number" then iconTex = tex end
                                        break
                                    end
                                end
                            end

                            -- 만약 여전히 134400(물음표)라면 Spell ID를 통해 C_Spell API로 텍스처를 시도
                            if iconTex == 134400 then
                                -- displayName을 통해 ID를 찾거나, 더 직관적으로 GetSpellTexture 시도
                                local ok, tex = pcall(function() return C_Spell.GetSpellTexture(spellName:gsub("^buff_", "")) end)
                                if ok and tex and not (issecretvalue and issecretvalue(tex)) and tex ~= 0 and tex ~= "" and type(tex) == "number" then
                                    iconTex = tex
                                end
                            end

            local iconStr = "|T" .. iconTex .. ":20:20:0:0:64:64:5:59:5:59|t "
            local arrowPrefix = "|cff888888(" .. count .. ")|r "
            local capturedSpell = spellName
            args["cdma_" .. count] = {
                type = "execute",
                name = arrowPrefix .. iconStr .. displayName,
                desc = (L["Click to unassign spell"] or "클릭시 할당 해제") .. "\n|cffaaaaaa" .. spellName .. "|r",
                order = 11 + (count * 0.01),
                -- [FIX] _dragData 추가 → GUI.lua가 새 스타일 (다크배경 + X버튼)로 렌더링
                _dragData = {
                    groupKey = "__cdm_spell__",
                    iconKey = capturedSpell,
                    iconIdx = count,
                },
                func = function()
                    if DDingUI.GroupManager then
                        DDingUI.GroupManager:UnassignSpell(capturedSpell)
                        SoftRefreshDynamicIcons()
                    end
                end,
            }
        end
    end

    -- [12.0.1] 2. 동적 그룹: CustomIcons 아이콘도 표시
    if gs and gs.groups and gs.groups[groupName] then
        local grpSettings = gs.groups[groupName]
        if grpSettings.sourceGroupKey then
            local dynDB = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.dynamicIcons
            local ciGroup = dynDB and dynDB.groups and dynDB.groups[grpSettings.sourceGroupKey]
            if ciGroup and ciGroup.icons then
                for iconIdx, iconKey in ipairs(ciGroup.icons) do
                    count = count + 1
                    local iconData = dynDB.iconData and dynDB.iconData[iconKey]
                    if iconData then
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
                            if type(spellID) == "string" then spellID = tonumber(spellID) or 0 end
                            
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
                        end
                        
                        local iconStr = "|T" .. iconTex .. ":20:20:0:0:64:64:5:59:5:59|t "
                        local orderBase = 11 + (count * 0.01)
                        local capturedSourceKey = grpSettings.sourceGroupKey
                        local capturedIconKey = iconKey
                        local totalIcons = #ciGroup.icons
                        local arrowPrefix = ""
                        if totalIcons > 1 then
                            arrowPrefix = "|cff888888[" .. iconIdx .. "]|r "
                        end
                        args["dyna_" .. count] = {
                            type = "execute",
                            name = arrowPrefix .. iconStr .. displayName,
                            desc = (L["Drag to reorder | Click to remove"] or "드래그: 순서 변경 | 클릭: 삭제"),
                            order = orderBase,
                            -- [FIX] 드래그&드롭 순서 변경용 데이터
                            _dragData = {
                                groupKey = capturedSourceKey,
                                iconKey = capturedIconKey,
                                iconIdx = iconIdx,
                            },
                            func = function()
                                -- [FIX] 관련 spellAssignments를 먼저 제거 (RemoveDynamicIcon이 iconData를 삭제하므로)
                                local gsCur = GetGS()
                                if gsCur and gsCur.spellAssignments then
                                    local dynDBCur = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.dynamicIcons
                                    local iconDataCur = dynDBCur and dynDBCur.iconData and dynDBCur.iconData[capturedIconKey]
                                    if iconDataCur and iconDataCur.id then
                                        local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(iconDataCur.id)
                                        if spellInfo and spellInfo.name then
                                            -- buff_ 접두사 버전과 일반 이름 둘 다 제거
                                            gsCur.spellAssignments["buff_" .. spellInfo.name] = nil
                                            gsCur.spellAssignments[spellInfo.name] = nil
                                        end
                                    end
                                end
                                -- 클릭 = 삭제
                                if DDingUI.CustomIcons and DDingUI.CustomIcons.RemoveDynamicIcon then
                                    DDingUI.CustomIcons:RemoveDynamicIcon(capturedIconKey)
                                end
                                SoftRefreshDynamicIcons()
                            end,
                        }
                    end
                end
            end
        end
    end

    if count == 0 then
        args.emptyAssigned = {
            type = "description",
            name = "|cff888888" .. (L["No manual assignments. Use Quick Assign or Spell ID below."] or "수동 할당 없음. 아래의 빠른 할당이나 입력창을 이용하세요.") .. "|r",
            order = 11,
            width = "full",
        }
    end

    return args
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
local function GetGroupCategory(groupName)
    local viewerKey = GROUP_VIEWER_MAP[groupName]
    if viewerKey == "BuffIconCooldownViewer" then return "buff" end
    if viewerKey then return "skill" end -- Essential/Utility
    local gs = GetGS()
    return gs and gs.groups[groupName] and gs.groups[groupName].groupCategory or "skill"
end

-- 헬퍼: group settings 읽기/쓰기 옵션 생성
-- [FIX] 핵심 3대 그룹(Cooldowns/Buffs/Utility)의 렌더링 관련 키는
-- profile.viewers[viewerName]에서 직접 읽고 씀 (GroupRenderer가 해당 테이블을 참조하므로)
local VIEWER_REDIRECT_KEYS = {
    iconSize = "iconSize",
    spacing = "spacing",
    aspectRatioCrop = "aspectRatioCrop",
    rowLimit = "rowLimit",
}

local function GS_Range(groupName, key, name, order, default, min, max, step, extra)
    local viewerName = GROUP_VIEWER_MAP[groupName]
    local viewerKey = viewerName and VIEWER_REDIRECT_KEYS[key]

    local opt = {
        type = "range", name = name, order = order, width = "full",
        min = min, max = max, step = step,
        get = function()
            -- 핵심 그룹 + 뷰어 연동 키 → profile.viewers[viewerName]에서 읽기
            if viewerKey then
                local profile = DDingUI.db and DDingUI.db.profile
                local vs = profile and profile.viewers and profile.viewers[viewerName]
                return vs and vs[viewerKey] or default
            end
            local gs = GetGS(); local g = gs and gs.groups[groupName]
            return g and g[key] or default
        end,
        set = function(_, val)
            -- 핵심 그룹 + 뷰어 연동 키 → profile.viewers[viewerName]에 쓰기
            if viewerKey then
                local profile = DDingUI.db and DDingUI.db.profile
                if profile then
                    profile.viewers = profile.viewers or {}
                    profile.viewers[viewerName] = profile.viewers[viewerName] or {}
                    profile.viewers[viewerName][viewerKey] = val
                end
            end
            -- groupSettings에도 동기화 (표시용 + 비뷰어 그룹 fallback)
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

local VIEWER_REDIRECT_SELECT_KEYS = {
    direction = "primaryDirection",
    growDirection = "secondaryDirection",
}

local function GS_Select(groupName, key, name, order, default, values)
    local viewerName = GROUP_VIEWER_MAP[groupName]
    local viewerKey = viewerName and VIEWER_REDIRECT_SELECT_KEYS[key]

    return {
        type = "select", name = name, order = order, width = "full", values = values,
        get = function()
            if viewerKey then
                local profile = DDingUI.db and DDingUI.db.profile
                local vs = profile and profile.viewers and profile.viewers[viewerName]
                return vs and vs[viewerKey] or default
            end
            local gs = GetGS(); local g = gs and gs.groups[groupName]
            return g and g[key] or default
        end,
        set = function(_, val)
            if viewerKey then
                local profile = DDingUI.db and DDingUI.db.profile
                if profile then
                    profile.viewers = profile.viewers or {}
                    profile.viewers[viewerName] = profile.viewers[viewerName] or {}
                    profile.viewers[viewerName][viewerKey] = val
                end
            end
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
        countTextAnchor = GS_Select(groupName, "countTextAnchor", L["Anchor"] or "앵커", 4, "BOTTOMRIGHT", ANCHOR_POINTS),
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

    -- CDM 그룹: 뷰어 옵션 한 번만 빌드
    local viewerOpts
    if isCDM and viewerKey and ns.CreateSingleViewerOptions then
        viewerOpts = ns.CreateSingleViewerOptions(viewerKey, displayName, 1)
    end

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
                    gs.groups[groupName].enabled = val; RefreshGroupSystem()
                end
            end,
        },
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
    -- [12.0.1] CDM 그룹: 레이아웃 옵션은 뷰어 설정(profile.viewers[viewerKey])에서 직접 읽기/쓰기
    -- GS_Range는 gs.groups[groupName]에 쓰지만 렌더러는 뷰어 설정을 읽으므로 CopyVO로 덮어씀
    if isCDM and viewerOpts and viewerOpts.args then
        local vo = viewerOpts.args
        -- [12.0.1] layoutOnly=true: 크기/간격/방향 변경은 레이아웃만 갱신 (깜빡임 방지)
        -- 외관
        if vo.iconSize then layoutArgs.iconSize = CopyVO(vo, "iconSize", 2, true) end
        if vo.spacing then layoutArgs.spacing = CopyVO(vo, "spacing", 3, true) end
        if vo.borderSize then layoutArgs.borderSize = CopyVO(vo, "borderSize", 4, true) end
        if vo.zoom then layoutArgs.zoom = CopyVO(vo, "zoom", 6, true) end
        if vo.aspectRatio then layoutArgs.aspectRatio = CopyVO(vo, "aspectRatio", 7, true) end
        -- 레이아웃
        if vo.primaryDirection then layoutArgs.direction = CopyVO(vo, "primaryDirection", 11, true) end
        if vo.secondaryDirection then layoutArgs.growDirection = CopyVO(vo, "secondaryDirection", 12, true) end
        if vo.rowLimit then layoutArgs.rowLimit = CopyVO(vo, "rowLimit", 13, true) end
    end

    -- [12.0.1] 커스텀 그룹: 레이아웃 옵션 setter를 RefreshGroupLayout()으로 교체
    -- GS_Range/GS_Select의 기본 setter는 RefreshGroupSystem()(=_forceFullSetup)을 호출하므로
    -- 아이콘 크기/간격/방향 변경 시 깜빡임 발생 → 레이아웃만 갱신하도록 변경
    if not isCDM then
        local LAYOUT_OPT_KEYS = {
            { arg = "iconSize",    dbKey = "iconSize" },
            { arg = "spacing",     dbKey = "spacing" },
            { arg = "borderSize",  dbKey = "borderSize" },
            { arg = "zoom",        dbKey = "zoom" },
            { arg = "aspectRatio", dbKey = "aspectRatioCrop" },
            { arg = "groupAlpha",  dbKey = "groupAlpha" },
            { arg = "rowLimit",    dbKey = "rowLimit" },
            -- [FIX] offsetX/offsetY 제거: 앵커 재적용이 필요하므로 RefreshGroupSystem() 유지
        }
        for _, info in ipairs(LAYOUT_OPT_KEYS) do
            local opt = layoutArgs[info.arg]
            if opt and opt.type == "range" then
                local dbKey = info.dbKey
                opt.set = function(_, val)
                    local gs = GetGS()
                    if gs and gs.groups[groupName] then
                        gs.groups[groupName][dbKey] = val
                        -- [FIX] 커스텀 그룹 레이아웃 직접 갱신 (Refresh 전체 경로 우회)
                        local GR = DDingUI.GroupRenderer
                        if GR and GR.RelayoutSingleGroup then
                            GR:RelayoutSingleGroup(groupName)
                        end
                        RefreshGroupSystem()
                    end
                end
            end
        end
        -- select 타입 (direction, growDirection)
        for _, argKey in ipairs({"direction", "growDirection"}) do
            local opt = layoutArgs[argKey]
            if opt and opt.type == "select" then
                local dbKey = argKey
                opt.set = function(_, val)
                    local gs = GetGS()
                    if gs and gs.groups[groupName] then
                        gs.groups[groupName][dbKey] = val
                        local GR = DDingUI.GroupRenderer
                        if GR and GR.RelayoutSingleGroup then
                            GR:RelayoutSingleGroup(groupName)
                        end
                        RefreshGroupSystem()
                    end
                end
            end
        end
    end

    -- 커스텀 그룹: 카테고리 선택 + 삭제 버튼
    if not isCDM then
        layoutArgs.categoryHeader = { type = "header", name = L["Group Category"] or "그룹 분류", order = 80 }
        layoutArgs.groupCategory = GS_Select(groupName, "groupCategory", L["Category"] or "분류", 81, "skill", CATEGORY_VALUES)
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
    args.layout = {
        type = "group",
        name = L["Layout"] or "배치",
        order = 10,
        args = layoutArgs,
    }

    -- ========== 2. 스펠 관리 ==========
    args.spellManagement = {
        type = "group",
        name = L["Spell Management"] or "스펠 관리",
        order = 20,
        args = {
            assignedHeader = { type = "header", name = L["Assigned Spells"] or "할당된 스펠", order = 10 },
            addSpellHeader = { type = "header", name = L["Add Spell"] or "스펠 추가", order = 20 },
            addSpell = {
                type = "spellSearch", -- [REFACTOR] Ayije 패턴 이식 — 실시간 Spell ID 검증
                name = L["Spell Name or ID"] or "스펠 이름 또는 ID",
                placeholder = "Spell ID...",
                buttonText = "추가",
                order = 21, width = "full",
                onAdd = function(val)
                    if isCDM then
                        -- CDM 그룹: spellAssignments 경로
                        local spellName = ResolveSpellInput(val, groupName)
                        if spellName and DDingUI.GroupManager then
                            DDingUI.GroupManager:AssignSpell(spellName, groupName)
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
                            -- buff_ 접두사 처리: 버프 뷰어 그룹이면 aura 타입
                            local targetViewer = GROUP_VIEWER_MAP[groupName]
                            local iconType = (targetViewer == "BuffIconCooldownViewer") and "aura" or "spell"
                            local sourceKey = EnsureSourceGroup(groupName)
                            local iconKey = ci:AddDynamicIcon({type = iconType, id = spellID})
                            if iconKey and sourceKey then
                                ci:MoveIconToGroup(iconKey, sourceKey)
                            end
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
            },
            iconGridHeader = { type = "header", name = L["Quick Assign"] or "빠른 할당", order = 30 },
            iconGrid = {
                type = "groupAssignGrid",
                name = L["Icon Assignment"] or "아이콘 할당",
                order = 31,
                groupName = groupName,
            },
            -- [12.0.1] 추가 옵션: 아이템/장신구 추가 (커스텀/동적 그룹 전용)
            -- CDM 그룹은 뷰어 기반이므로 CustomIcons 아이템 추가 불가
            advancedHeader = not isCDM and { type = "header", name = L["Advanced Add"] or "추가 옵션 (아이템/장신구)", order = 40 } or nil,
            addItemID = not isCDM and {
                type = "spellSearch",
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
            addTrinket1 = not isCDM and {
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
            addTrinket2 = not isCDM and {
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
            advancedDesc = not isCDM and {
                type = "description", order = 44,
                name = "|cff888888" .. (L["Trinkets auto-detect proc buffs and show item cooldown. Fallback items can be configured per-icon in Dynamic Icons tab."] or "장신구는 발동 버프를 자동 감지하고 아이템 쿨다운을 표시합니다. 폴백 아이템은 동적 아이콘 탭에서 아이콘별로 설정 가능합니다.") .. "|r",
            } or nil,
        },
    }

    -- [REFACTOR] 할당된 스펠 목록을 병합 (인라인 그룹 충돌 우회)
    local assignedArgs = BuildAssignedSpellsArgs(groupName)
    for k, v in pairs(assignedArgs) do
        args.spellManagement.args[k] = v
    end

    -- ========== 3. 시각 효과 ==========
    local visualArgs
    if isCDM and viewerOpts and viewerOpts.args then
        local vo = viewerOpts.args
        visualArgs = {}

        -- [3-1] 쿨다운 스와이프
        visualArgs.sec01_swipeHeader = { type = "header", name = L["Cooldown Swipe"] or "쿨다운 스와이프", order = 1 }
        visualArgs.sec01_swipeReverse    = GS_Toggle(groupName, "swipeReverse", L["Reverse Swipe"] or "스와이프 반전", 2, true)
        visualArgs.sec01_swipeColor      = GS_Color(groupName, "swipeColor", L["Swipe Color"] or "스와이프 색상", 3, {0,0,0,0.8})
        visualArgs.disableSwipeAnimation = CopyVO(vo, "disableSwipeAnimation", 4)
        visualArgs.auraSwipeColor        = CopyVO(vo, "auraSwipeColor", 5)
        visualArgs.resetAuraSwipeColor   = CopyVO(vo, "resetAuraSwipeColor", 6)

        -- [3-2] 그림자
        visualArgs.sec02_shadowHeader    = { type = "header", name = L["Shadow"] or "그림자", order = 10 }
        visualArgs.cooldownShadowOffsetX = CopyVO(vo, "cooldownShadowOffsetX", 11)
        visualArgs.cooldownShadowOffsetY = CopyVO(vo, "cooldownShadowOffsetY", 12)

        -- [3-3] 애니메이션 설정
        visualArgs.sec03_animHeader      = { type = "header", name = L["Animation"] or "애니메이션 설정", order = 20 }
        visualArgs.disableEdgeGlow       = CopyVO(vo, "disableEdgeGlow", 21)
        visualArgs.disableBlingAnimation = CopyVO(vo, "disableBlingAnimation", 22)

        -- [3-4] 보조 강조 효과
        visualArgs.sec04_assistHeader         = { type = "header", name = L["Assist Highlight"] or "보조 강조 효과", order = 30 }
        visualArgs.assistHighlightEnabled     = CopyVO(vo, "assistHighlightEnabled", 31)
        visualArgs.assistHighlightType        = CopyVO(vo, "assistHighlightType", 32)
        visualArgs.assistFlipbookScale        = CopyVO(vo, "assistFlipbookScale", 33)
        visualArgs.assistGlowType             = CopyVO(vo, "assistGlowType", 34)
        visualArgs.assistGlowColor            = CopyVO(vo, "assistGlowColor", 35)
        visualArgs.assistGlowLines            = CopyVO(vo, "assistGlowLines", 36)
        visualArgs.assistGlowFrequency        = CopyVO(vo, "assistGlowFrequency", 37)
        visualArgs.assistGlowThickness        = CopyVO(vo, "assistGlowThickness", 38)
        visualArgs.assistHighlightPixelLength = CopyVO(vo, "assistHighlightPixelLength", 39)

        -- [3-5] 아이콘 글로우 (프록)
        visualArgs.sec05_glowHeader          = { type = "header", name = L["Icon Glow"] or "아이콘 글로우", order = 40 }
        visualArgs.auraGlow                  = CopyVO(vo, "auraGlow", 41)
        visualArgs.auraGlowType              = CopyVO(vo, "auraGlowType", 42)
        visualArgs.auraGlowColor             = CopyVO(vo, "auraGlowColor", 43)
        visualArgs.auraGlowPixelLines        = CopyVO(vo, "auraGlowPixelLines", 44)
        visualArgs.auraGlowPixelFrequency    = CopyVO(vo, "auraGlowPixelFrequency", 45)
        visualArgs.auraGlowPixelThickness    = CopyVO(vo, "auraGlowPixelThickness", 46)
        visualArgs.auraGlowPixelLength       = CopyVO(vo, "auraGlowPixelLength", 47)
        visualArgs.auraGlowAutocastParticles = CopyVO(vo, "auraGlowAutocastParticles", 48)
        visualArgs.auraGlowAutocastFrequency = CopyVO(vo, "auraGlowAutocastFrequency", 49)
        visualArgs.auraGlowAutocastScale     = CopyVO(vo, "auraGlowAutocastScale", 50)
        visualArgs.auraGlowButtonFrequency   = CopyVO(vo, "auraGlowButtonFrequency", 51)
        visualArgs.procGlowEnabled           = CopyVO(vo, "procGlowEnabled", 52)
        visualArgs.procGlowType              = CopyVO(vo, "procGlowType", 53)
        visualArgs.procGlowColor             = CopyVO(vo, "procGlowColor", 54)
        visualArgs.procGlowPixelLines        = CopyVO(vo, "procGlowPixelLines", 55)
        visualArgs.procGlowPixelFrequency    = CopyVO(vo, "procGlowPixelFrequency", 56)
        visualArgs.procGlowPixelThickness    = CopyVO(vo, "procGlowPixelThickness", 57)
        visualArgs.procGlowPixelLength       = CopyVO(vo, "procGlowPixelLength", 58)
        visualArgs.procGlowAutocastParticles = CopyVO(vo, "procGlowAutocastParticles", 59)
        visualArgs.procGlowAutocastFrequency = CopyVO(vo, "procGlowAutocastFrequency", 60)
        visualArgs.procGlowAutocastScale     = CopyVO(vo, "procGlowAutocastScale", 61)
        visualArgs.procGlowButtonFrequency   = CopyVO(vo, "procGlowButtonFrequency", 62)

        -- [3-6] 생존기/쿨기 스와이프 글로우
        visualArgs.sec06_survivalHeader = { type = "header", name = L["Personal Swipe Glow"] or "생존기 스와이프 글로우", order = 70 }
        local swcOpt = CopyVO(vo, "swipeColor", 71)
        if swcOpt then visualArgs.viewerSwipeColor = swcOpt end
        local swrOpt = CopyVO(vo, "swipeReverse", 72)
        if swrOpt then visualArgs.viewerSwipeReverse = swrOpt end
    else
        -- 커스텀 그룹: group settings 기반 시각 효과
        visualArgs = BuildCustomVisualArgs(groupName)
    end
    args.visual = {
        type = "group",
        name = L["Visual Effects"] or "시각 효과",
        order = 30,
        args = visualArgs,
    }

    -- ========== 4. 텍스트 ==========
    local textArgs
    if isCDM and viewerOpts and viewerOpts.args then
        local vo = viewerOpts.args
        textArgs = {}

        -- [4-1] 충전 / 중첩 텍스트
        textArgs.sec01_chargeHeader = { type = "header", name = L["Stack Text"] or "충전 / 중첩 텍스트", order = 1 }
        textArgs.countTextFont    = CopyVO(vo, "countTextFont", 2)
        textArgs.countTextSize    = CopyVO(vo, "countTextSize", 3)
        textArgs.countTextColor   = CopyVO(vo, "countTextColor", 4)
        textArgs.chargeTextAnchor = CopyVO(vo, "chargeTextAnchor", 5)
        textArgs.countTextOffsetX = CopyVO(vo, "countTextOffsetX", 6)
        textArgs.countTextOffsetY = CopyVO(vo, "countTextOffsetY", 7)

        -- [4-2] 쿨다운 텍스트
        textArgs.sec02_cdHeader = { type = "header", name = L["Cooldown Text"] or "쿨다운 텍스트", order = 10 }
        textArgs.hideDurationText    = CopyVO(vo, "hideDurationText", 10.5)
        textArgs.cooldownFont        = CopyVO(vo, "cooldownFont", 11)
        textArgs.cooldownFontSize    = CopyVO(vo, "cooldownFontSize", 12)
        textArgs.cooldownTextColor   = CopyVO(vo, "cooldownTextColor", 13)
        textArgs.cooldownTextAnchor  = CopyVO(vo, "cooldownTextAnchor", 14)
        textArgs.cooldownTextOffsetX = CopyVO(vo, "cooldownTextOffsetX", 15)
        textArgs.cooldownTextOffsetY = CopyVO(vo, "cooldownTextOffsetY", 16)
        textArgs.cooldownTextFormat  = CopyVO(vo, "cooldownTextFormat", 17)

        -- [4-3] 강화 효과 지속시간 텍스트 (BuffIcon only)
        if viewerKey == "BuffIconCooldownViewer" then
            textArgs.sec03_durHeader     = { type = "header", name = L["Duration Text"] or "강화 효과 지속시간 텍스트", order = 20 }
            textArgs.durationTextAnchor  = CopyVO(vo, "durationTextAnchor", 21)
            textArgs.durationTextOffsetX = CopyVO(vo, "durationTextOffsetX", 22)
            textArgs.durationTextOffsetY = CopyVO(vo, "durationTextOffsetY", 23)
            textArgs.durationTextFont    = CopyVO(vo, "durationTextFont", 24)
            textArgs.durationTextSize    = CopyVO(vo, "durationTextSize", 25)
            textArgs.durationTextColor   = CopyVO(vo, "durationTextColor", 26)
        end

        -- [4-4] 단축키 텍스트 (Essential/Utility only)
        if viewerKey == "EssentialCooldownViewer" or viewerKey == "UtilityCooldownViewer" then
            textArgs.sec04_keybindHeader = { type = "header", name = L["Keybind Text"] or "단축키 텍스트", order = 30 }
            textArgs.showKeybinds     = CopyVO(vo, "showKeybinds", 31)
            textArgs.keybindFont      = CopyVO(vo, "keybindFont", 32)
            textArgs.keybindFontSize  = CopyVO(vo, "keybindFontSize", 33)
            textArgs.keybindFontColor = CopyVO(vo, "keybindFontColor", 34)
            textArgs.keybindAnchor    = CopyVO(vo, "keybindAnchor", 35)
            textArgs.keybindOffsetX   = CopyVO(vo, "keybindOffsetX", 36)
            textArgs.keybindOffsetY   = CopyVO(vo, "keybindOffsetY", 37)
        end
    else
        -- 커스텀 그룹: group settings 기반 텍스트 (카테고리별)
        textArgs = BuildCustomTextArgs(groupName, category)
    end
    args.text = {
        type = "group",
        name = L["Text"] or "텍스트",
        order = 40,
        args = textArgs,
    }

    -- ========== 5. 뷰어 (CDM 그룹 전용) ==========
    if isCDM and viewerOpts and viewerOpts.args then
        local vo = viewerOpts.args
        local viewerDetailArgs = {}

        -- 그룹 오프셋 (파티/레이드) — 오프셋 0이면 비활성화와 동일
        viewerDetailArgs.sec02_offsetHeader = { type = "header", name = L["Group Offsets"] or "그룹 오프셋 (파티/레이드)", order = 1 }
        viewerDetailArgs.groupOffsetDesc = CopyVO(vo, "groupOffsetDesc", 2)
        viewerDetailArgs.partyOffsetX    = CopyVO(vo, "partyOffsetX", 3)
        viewerDetailArgs.partyOffsetY    = CopyVO(vo, "partyOffsetY", 4)
        viewerDetailArgs.raidOffsetX     = CopyVO(vo, "raidOffsetX", 5)
        viewerDetailArgs.raidOffsetY     = CopyVO(vo, "raidOffsetY", 6)

        args.viewer = {
            type = "group",
            name = L["Group Offsets"] or "오프셋",
            order = 50,
            args = viewerDetailArgs,
        }
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
