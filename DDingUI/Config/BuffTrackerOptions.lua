local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
local L = ns.L or LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME, true)
local LSM = LibStub("LibSharedMedia-3.0")
local SL = _G.DDingUI_StyleLib -- [12.0.1]
local FLAT = (SL and SL.Textures and SL.Textures.flat) or "Interface\\Buttons\\WHITE8x8" -- [12.0.1]
local CDM_PREFIX = (SL and SL.GetChatPrefix and SL.GetChatPrefix("CDM", "CDM")) or "|cffffffffDDing|r|cffffa300UI|r |cffe6731fCDM|r: " -- [STYLE]
-- [REFACTOR] AceGUI → StyleLib: AceConfigRegistry, AceConfigDialog 제거
local buildVersion = select(4, GetBuildInfo())

-- Get current specialization ID (unique across all classes)
local function GetCurrentSpecID()
    local specIndex = GetSpecialization()
    if not specIndex then
        return nil
    end
    local specID = GetSpecializationInfo(specIndex)
    return specID
end

-- [FIX] SpecProfiles 스냅샷 갱신 (설정 변경 시 호출)
local function MarkSpecDirty()
    if DDingUI.SpecProfiles and DDingUI.SpecProfiles.MarkDirty then
        DDingUI.SpecProfiles:MarkDirty()
    end
end

-- ============================================================
-- SPELL SCHOOL COLOR MAPPING (주문 계열별 바 색상)
-- ============================================================
local SPELL_SCHOOL_COLORS = {
    [1] = { 0.85, 0.75, 0.60, 1 },   -- Physical (tan/brown)
    [2] = { 1.00, 0.90, 0.50, 1 },   -- Holy (yellow/gold)
    [4] = { 1.00, 0.50, 0.20, 1 },   -- Fire (orange)
    [8] = { 0.40, 0.85, 0.30, 1 },   -- Nature (green)
    [16] = { 0.40, 0.70, 1.00, 1 },  -- Frost (blue)
    [32] = { 0.70, 0.40, 0.90, 1 },  -- Shadow (purple)
    [64] = { 0.50, 0.50, 1.00, 1 },  -- Arcane (violet)
}

-- Default color when spell school is unknown
local DEFAULT_BAR_COLOR = { 1, 0.8, 0, 1 }

-- Get bar color based on spell school
local function GetSpellSchoolColor(spellID)
    if not spellID or spellID == 0 then
        return DEFAULT_BAR_COLOR
    end

    local schoolMask = nil

    -- Method 1: Try C_UnitAuras.GetPlayerAuraBySpellID (works if buff is active)
    pcall(function()
        local auraData = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
        if auraData and auraData.dispelName then
            -- Map dispel type to school
            local dispelSchools = {
                ["Magic"] = 64,    -- Arcane
                ["Curse"] = 32,    -- Shadow
                ["Disease"] = 8,   -- Nature
                ["Poison"] = 8,    -- Nature
            }
            schoolMask = dispelSchools[auraData.dispelName]
        end
        -- Some auras have isHarmful which could hint at school
        if auraData and auraData.spellSchool then
            schoolMask = auraData.spellSchool
        end
    end)

    -- Method 2: Try GetSpellPowerCost for school info
    if not schoolMask then
        pcall(function()
            local costInfo = C_Spell.GetSpellPowerCost(spellID)
            if costInfo and costInfo[1] then
                -- Power type can hint at school (mana = arcane, rage = physical, etc.)
                local powerSchools = {
                    [Enum.PowerType.Mana] = 64,      -- Arcane
                    [Enum.PowerType.Rage] = 1,       -- Physical
                    [Enum.PowerType.Energy] = 1,    -- Physical
                    [Enum.PowerType.RunicPower] = 16, -- Frost
                    [Enum.PowerType.HolyPower] = 2,  -- Holy
                    [Enum.PowerType.Maelstrom] = 8,  -- Nature
                    [Enum.PowerType.Fury] = 4,       -- Fire (DH)
                }
                if powerSchools[costInfo[1].type] then
                    schoolMask = powerSchools[costInfo[1].type]
                end
            end
        end)
    end

    -- If we got a school mask, find the primary school color
    if schoolMask and schoolMask > 0 then
        -- Check for single school (power of 2)
        if SPELL_SCHOOL_COLORS[schoolMask] then
            return SPELL_SCHOOL_COLORS[schoolMask]
        end
        -- Multi-school: find the highest bit (most "exotic" school)
        for _, school in ipairs({64, 32, 16, 8, 4, 2, 1}) do
            if bit.band(schoolMask, school) > 0 and SPELL_SCHOOL_COLORS[school] then
                return SPELL_SCHOOL_COLORS[school]
            end
        end
    end

    return DEFAULT_BAR_COLOR
end

-- ============================================================
-- CUSTOM DIALOG FOR BUFF SELECTION (5 buttons: Bar, Icon, Sound, Text, Cancel)
-- ============================================================

-- Temp storage for pending buff entry
local pendingBuffEntry = nil
local addBuffDialog = nil

-- Helper function to style dialog buttons with DDingUI theme
local function StyleDialogButton(button, text, THEME, StyleFontString)
    button:SetBackdrop({
        bgFile = FLAT,
        edgeFile = FLAT,
        tile = false,
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    button:SetBackdropColor(THEME.bgWidget[1], THEME.bgWidget[2], THEME.bgWidget[3], 1)
    button:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 1)

    -- Remove default textures
    if button:GetNormalTexture() then button:GetNormalTexture():SetAlpha(0) end
    if button:GetPushedTexture() then button:GetPushedTexture():SetAlpha(0) end
    if button:GetHighlightTexture() then button:GetHighlightTexture():SetAlpha(0) end
    if button:GetDisabledTexture() then button:GetDisabledTexture():SetAlpha(0) end

    -- Create custom label
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if StyleFontString then StyleFontString(label) end
    label:SetPoint("CENTER")
    label:SetText(text)
    label:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3], 0.9)
    button.label = label

    -- Hide original text
    local originalText = button:GetFontString()
    if originalText then originalText:SetAlpha(0) end

    -- Hover effects
    button:SetScript("OnEnter", function(self)
        self:SetBackdropColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.8)
        self:SetBackdropBorderColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
        if self.label then self.label:SetTextColor(1, 1, 1, 1) end
    end)

    button:SetScript("OnLeave", function(self)
        self:SetBackdropColor(THEME.bgWidget[1], THEME.bgWidget[2], THEME.bgWidget[3], 1)
        self:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 1)
        if self.label then self.label:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3], 0.9) end
    end)
end

-- Create custom dialog frame
local function CreateAddBuffDialog()
    if addBuffDialog then return addBuffDialog end

    -- Get DDingUI theme and styling helpers
    local GUI = DDingUI.GUI or {}
    local THEME = GUI.THEME or {
        bgMain = {0.10, 0.10, 0.10, 0.95},
        bgWidget = {0.06, 0.06, 0.06, 0.80},
        border = {0.25, 0.25, 0.25, 0.50},
        text = {0.85, 0.85, 0.85, 1},
        textDim = {0.60, 0.60, 0.60, 1},
        accent = {0.90, 0.45, 0.12},
        gold = {0.90, 0.45, 0.12, 1},
    }
    local StyleFontString = GUI.StyleFontString
    local CreateShadow = GUI.CreateShadow

    local frame = CreateFrame("Frame", "DDingUI_AddBuffDialog", UIParent, "BackdropTemplate")
    frame:SetSize(320, 195)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(200)

    -- DDingUI styled backdrop
    frame:SetBackdrop({
        bgFile = FLAT,
        edgeFile = FLAT,
        tile = false,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    frame:SetBackdropColor(THEME.bgMain[1], THEME.bgMain[2], THEME.bgMain[3], THEME.bgMain[4] or 0.98)
    frame:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], THEME.border[4] or 0.5)

    -- Add shadow effect
    if CreateShadow then
        CreateShadow(frame, 4)
    end

    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:Hide()

    -- Create a title bar for dragging (so buttons can still be clicked)
    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetHeight(40)
    titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)

    -- Title
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    if StyleFontString then StyleFontString(frame.title) end
    frame.title:SetPoint("TOP", 0, -20)
    frame.title:SetText("")
    frame.title:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3], 1)

    -- Question text
    frame.question = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    if StyleFontString then StyleFontString(frame.question) end
    frame.question:SetPoint("TOP", frame.title, "BOTTOM", 0, -10)
    frame.question:SetText(L["How would you like to display this buff?"] or "How would you like to display this buff?")
    frame.question:SetTextColor(THEME.gold[1], THEME.gold[2], THEME.gold[3], 1)

    -- Button width and spacing
    local btnWidth = 70
    local btnHeight = 24
    local spacing = 6
    local totalWidth = (btnWidth * 4) + (spacing * 3)
    local startX = -totalWidth / 2 + btnWidth / 2

    -- Helper to create styled button with click handler
    local function CreateDialogButton(parent, width, height, text, onClick)
        local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
        btn:SetSize(width, height)
        btn:EnableMouse(true)
        btn:SetFrameLevel(parent:GetFrameLevel() + 10)
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        StyleDialogButton(btn, text, THEME, StyleFontString)
        btn:SetScript("OnClick", function(self, mouseButton)
            if onClick then
                onClick(self, mouseButton)
            end
        end)
        return btn
    end

    -- Bar button
    frame.barBtn = CreateDialogButton(frame, btnWidth, btnHeight, L["Bar"] or "Bar", function()
        if pendingBuffEntry then
            DDingUI.AddTrackedBuff(pendingBuffEntry, "bar")
            pendingBuffEntry = nil
        end
        frame:Hide()
    end)
    frame.barBtn:SetPoint("TOP", frame.question, "BOTTOM", startX, -20)

    -- Ring button (new)
    frame.ringBtn = CreateDialogButton(frame, btnWidth, btnHeight, L["Ring"] or "Ring", function()
        if pendingBuffEntry then
            DDingUI.AddTrackedBuff(pendingBuffEntry, "ring")
            pendingBuffEntry = nil
        end
        frame:Hide()
    end)
    frame.ringBtn:SetPoint("LEFT", frame.barBtn, "RIGHT", spacing, 0)

    -- Icon button
    frame.iconBtn = CreateDialogButton(frame, btnWidth, btnHeight, L["Icon"] or "Icon", function()
        if pendingBuffEntry then
            DDingUI.AddTrackedBuff(pendingBuffEntry, "icon")
            pendingBuffEntry = nil
        end
        frame:Hide()
    end)
    frame.iconBtn:SetPoint("LEFT", frame.ringBtn, "RIGHT", spacing, 0)

    -- Sound button
    frame.soundBtn = CreateDialogButton(frame, btnWidth, btnHeight, L["Sound"] or "Sound", function()
        if pendingBuffEntry then
            DDingUI.AddTrackedBuff(pendingBuffEntry, "sound")
            pendingBuffEntry = nil
        end
        frame:Hide()
    end)
    frame.soundBtn:SetPoint("LEFT", frame.iconBtn, "RIGHT", spacing, 0)

    -- Row 2: Text + Trigger buttons (side by side)
    local row2Spacing = 6
    local row2TotalWidth = (btnWidth * 2) + row2Spacing
    local row2StartX = -row2TotalWidth / 2 + btnWidth / 2

    frame.textBtn = CreateDialogButton(frame, btnWidth, btnHeight, L["Text"] or "Text", function()
        if pendingBuffEntry then
            DDingUI.AddTrackedBuff(pendingBuffEntry, "text")
            pendingBuffEntry = nil
        end
        frame:Hide()
    end)
    frame.textBtn:SetPoint("TOP", frame, "TOP", row2StartX, -125)

    frame.triggerBtn = CreateDialogButton(frame, btnWidth, btnHeight, L["Trigger"] or "Trigger", function()
        if pendingBuffEntry then
            DDingUI.AddTrackedBuff(pendingBuffEntry, "trigger")
            pendingBuffEntry = nil
        end
        frame:Hide()
    end)
    frame.triggerBtn:SetPoint("LEFT", frame.textBtn, "RIGHT", row2Spacing, 0)

    -- Row 3: Cancel button (centered)
    frame.cancelBtn = CreateDialogButton(frame, 100, btnHeight, L["Cancel"] or "Cancel", function()
        pendingBuffEntry = nil
        frame:Hide()
    end)
    frame.cancelBtn:SetPoint("TOP", frame, "TOP", 0, -157)

    -- Register with UISpecialFrames so ESC closes the dialog
    tinsert(UISpecialFrames, "DDingUI_AddBuffDialog")

    addBuffDialog = frame
    return frame
end

-- Helper function to show the dialog with entry
local function ShowAddTrackedBuffDialog(entry)
    pendingBuffEntry = entry
    local dialog = CreateAddBuffDialog()
    local icon = entry.icon and string.format("|T%d:20:20:0:0|t ", entry.icon) or ""
    dialog.title:SetText(icon .. (entry.name or "Unknown Buff"))
    -- [REFACTOR] 유형에 따라 질문 텍스트 분기
    if entry.isAura then
        dialog.question:SetText(L["How would you like to display this buff?"] or "이 강화 효과를 어떻게 표시할까요?")
    else
        dialog.question:SetText(L["How would you like to display this ability?"] or "이 능력을 어떻게 표시할까요?")
    end
    dialog:Show()
    dialog:Raise()  -- Ensure dialog is on top
end

-- ============================================================
-- TRACKED BUFFS MANAGEMENT
-- ============================================================

-- Get tracked buffs array (db.global 사용 - 같은 전문화 캐릭터 간 공유)
-- specID is unique across all classes, so different characters won't collide
local function GetTrackedBuffs()
    if not DDingUI.db then return {} end

    local specID = GetCurrentSpecID()
    if not specID then return {} end

    -- db.global.trackedBuffsPerSpec 초기화
    if not DDingUI.db.global.trackedBuffsPerSpec then
        DDingUI.db.global.trackedBuffsPerSpec = {}
    end
    local globalStore = DDingUI.db.global.trackedBuffsPerSpec

    -- [FIX] Migration: profile → global (병합 방식 — 중복 제거 후 추가)
    local rootCfg = DDingUI.db.profile and DDingUI.db.profile.buffTrackerBar
    if rootCfg and rootCfg.trackedBuffsPerSpec then
        for oldSpecID, oldData in pairs(rootCfg.trackedBuffsPerSpec) do
            if type(oldData) == "table" and #oldData > 0 then
                if not globalStore[oldSpecID] then
                    globalStore[oldSpecID] = {}
                end
                local existing = globalStore[oldSpecID]
                local existingKeys = {}
                for _, buff in ipairs(existing) do
                    local key = tostring(buff.cooldownID or 0) .. "_" .. (buff.displayType or "bar")
                    existingKeys[key] = true
                end
                for _, buff in ipairs(oldData) do
                    local key = tostring(buff.cooldownID or 0) .. "_" .. (buff.displayType or "bar")
                    if not existingKeys[key] then
                        local copy = {}
                        for k, v in pairs(buff) do
                            if type(v) == "table" then
                                copy[k] = {}
                                for k2, v2 in pairs(v) do
                                    copy[k][k2] = v2
                                end
                            else
                                copy[k] = v
                            end
                        end
                        table.insert(existing, copy)
                        existingKeys[key] = true
                    end
                end
            end
        end
        rootCfg.trackedBuffsPerSpec = nil
    end

    -- [FIX] Legacy migration (병합 방식)
    if rootCfg and not rootCfg._legacyMigrationComplete
       and rootCfg.trackedBuffs and #rootCfg.trackedBuffs > 0 then
        if not globalStore[specID] then
            globalStore[specID] = {}
        end
        local existing = globalStore[specID]
        local existingKeys = {}
        for _, buff in ipairs(existing) do
            local key = tostring(buff.cooldownID or 0) .. "_" .. (buff.displayType or "bar")
            existingKeys[key] = true
        end
        for _, buff in ipairs(rootCfg.trackedBuffs) do
            local key = tostring(buff.cooldownID or 0) .. "_" .. (buff.displayType or "bar")
            if not existingKeys[key] then
                local copy = {}
                for k, v in pairs(buff) do
                    if type(v) == "table" then
                        copy[k] = {}
                        for k2, v2 in pairs(v) do
                            copy[k][k2] = v2
                        end
                    else
                        copy[k] = v
                    end
                end
                table.insert(existing, copy)
                existingKeys[key] = true
            end
        end
        rootCfg._legacyMigrationComplete = true
        rootCfg.trackedBuffs = {}
    end

    if not globalStore[specID] then
        globalStore[specID] = {}
    end

    return globalStore[specID]
end

-- UID 생성 (고유 식별자: 순서 변경에도 불변)
local _uidCounter = 0
local function GenerateUID()
    _uidCounter = _uidCounter + 1
    return string.format("bt_%x_%x", time(), _uidCounter + math.random(1000, 9999))
end

-- 기존 오라에 uid 없으면 자동 부여 (마이그레이션)
function DDingUI.EnsureTrackedBuffUIDs()
    local trackedBuffs = GetTrackedBuffs()
    if not trackedBuffs then return end
    for i, buff in ipairs(trackedBuffs) do
        if not buff.uid then
            buff.uid = GenerateUID()
        end
    end
end

-- uid로 현재 인덱스 찾기
function DDingUI.FindTrackedBuffByUID(uid)
    if not uid then return nil end
    local trackedBuffs = GetTrackedBuffs()
    if not trackedBuffs then return nil end
    for i, buff in ipairs(trackedBuffs) do
        if buff.uid == uid then
            return i, buff
        end
    end
    return nil
end

-- [REFACTOR] AceGUI → StyleLib: AceConfigRegistry/AceConfigDialog 폴백 제거
-- Refresh options panel to reflect changes (always preserves tab position)
-- NOTE: This function must be defined before AddTrackedBuff/RemoveTrackedBuff
local function RefreshOptions()
    -- C_Timer.After(0): 현재 OnClick 핸들러 완료 후 다음 프레임에서 재렌더
    -- (클릭된 버튼이 ClearTabContent로 파괴되면서 UI 스택 꼬이는 문제 방지)
    C_Timer.After(0, function()
        local configFrame = _G["DDingUI_ConfigFrame"]
        local btPanel = configFrame and configFrame.contentArea and configFrame.contentArea._btPanel
        if btPanel and btPanel.selectedIndex and btPanel:IsShown() then
            local trackedBuffs = GetTrackedBuffs()
            local selected = trackedBuffs[btPanel.selectedIndex]
            if selected then
                local ok, err
                if selected.isGroup and btPanel.RenderGroupSettings then
                    ok, err = pcall(btPanel.RenderGroupSettings, btPanel, btPanel.selectedIndex)
                elseif btPanel.RenderTrackerTabs then
                    ok, err = pcall(btPanel.RenderTrackerTabs, btPanel, btPanel.selectedIndex)
                end
                if not ok and err then
                    print("|cffff4444[DDingUI] RefreshOptions error:|r " .. tostring(err))
                end
                return
            end
        end
        DDingUI:RefreshConfigGUI(true)
    end)
end

-- Move tracked buff up (-1) or down (+1) in the list
function DDingUI.MoveTrackedBuff(index, direction)
    local trackedBuffs = GetTrackedBuffs()
    if not trackedBuffs or not trackedBuffs[index] then return end

    local newIndex = index + direction
    if newIndex < 1 or newIndex > #trackedBuffs then return end

    -- 각 엔트리에 원래 인덱스 태그
    for i = 1, #trackedBuffs do
        trackedBuffs[i]._origIdx = i
    end

    -- swap
    trackedBuffs[index], trackedBuffs[newIndex] = trackedBuffs[newIndex], trackedBuffs[index]

    -- 인덱스 매핑 테이블
    local idxMap = {}
    for i = 1, #trackedBuffs do
        if trackedBuffs[i]._origIdx then
            idxMap[trackedBuffs[i]._origIdx] = i
        end
    end

    -- parentGroup 재매핑
    for i = 1, #trackedBuffs do
        if trackedBuffs[i].parentGroup then
            trackedBuffs[i].parentGroup = idxMap[trackedBuffs[i].parentGroup] or trackedBuffs[i].parentGroup
        end
    end

    -- controlledChildren 재매핑
    for i = 1, #trackedBuffs do
        if trackedBuffs[i].isGroup and trackedBuffs[i].controlledChildren then
            local newCC = {}
            for _, oldCI in ipairs(trackedBuffs[i].controlledChildren) do
                local newCI = idxMap[oldCI]
                if newCI then table.insert(newCC, newCI) end
            end
            trackedBuffs[i].controlledChildren = newCC
        end
    end

    -- attachTo 재매핑 (DDingUIBuffTrackerBar/Icon/Text + 인덱스)
    local ATTACH_PATTERNS = {
        "DDingUIBuffTrackerBar",
        "DDingUIBuffTrackerIcon",
        "DDingUIBuffTrackerText",
    }
    for i = 1, #trackedBuffs do
        local d = trackedBuffs[i].display
        local s = trackedBuffs[i].settings
        for _, pat in ipairs(ATTACH_PATTERNS) do
            if d and type(d.attachTo) == "string" then
                local oldNum = tonumber(d.attachTo:match("^" .. pat .. "(%d+)$"))
                if oldNum and idxMap[oldNum] then
                    d.attachTo = pat .. idxMap[oldNum]
                end
            end
            if s and type(s.attachTo) == "string" then
                local oldNum = tonumber(s.attachTo:match("^" .. pat .. "(%d+)$"))
                if oldNum and idxMap[oldNum] then
                    s.attachTo = pat .. idxMap[oldNum]
                end
            end
        end
    end

    -- 임시 태그 제거
    for i = 1, #trackedBuffs do
        trackedBuffs[i]._origIdx = nil
    end
end

-- Duplicate tracked buff (deep copy)
function DDingUI.DuplicateTrackedBuff(index)
    local trackedBuffs = GetTrackedBuffs()
    if not trackedBuffs or not trackedBuffs[index] then return end

    -- 딥카피 함수
    local function deepCopy(orig)
        if type(orig) ~= "table" then return orig end
        local copy = {}
        for k, v in pairs(orig) do
            copy[k] = deepCopy(v)
        end
        return copy
    end

    local original = trackedBuffs[index]
    local duplicate = deepCopy(original)
    duplicate.uid = GenerateUID()  -- 복제본은 새 uid
    duplicate.name = (duplicate.name or "Tracker") .. " (Copy)"

    -- 그룹이면 자식은 복제하지 않음 (빈 그룹으로)
    if duplicate.isGroup then
        duplicate.controlledChildren = {}
    end

    -- 원본 바로 뒤에 삽입
    table.insert(trackedBuffs, index + 1, duplicate)

    -- 삽입으로 인한 인덱스 밀림 보정
    for i = 1, #trackedBuffs do
        if trackedBuffs[i].parentGroup and trackedBuffs[i].parentGroup > index then
            trackedBuffs[i].parentGroup = trackedBuffs[i].parentGroup + 1
        end
        if trackedBuffs[i].isGroup and trackedBuffs[i].controlledChildren then
            for ci = 1, #trackedBuffs[i].controlledChildren do
                if trackedBuffs[i].controlledChildren[ci] > index then
                    trackedBuffs[i].controlledChildren[ci] = trackedBuffs[i].controlledChildren[ci] + 1
                end
            end
        end
    end
end

-- Add a new tracked buff
function DDingUI.AddTrackedBuff(entry, displayType)
    if not entry or not entry.cooldownID then return end

    local trackedBuffs = GetTrackedBuffs()

    -- Check if already tracked with same displayType
    -- (같은 버프를 여러 타입으로 추적 가능: bar, icon, sound, text)
    for _, buff in ipairs(trackedBuffs) do
        if buff.cooldownID == entry.cooldownID and buff.displayType == displayType then
            local typeNames = {
                bar = L["Bar"] or "Bar",
                ring = L["Ring"] or "Ring",
                icon = L["Icon"] or "Icon",
                sound = L["Sound"] or "Sound",
                text = L["Text"] or "Text",
                trigger = L["Trigger"] or "Trigger",
            }
            local typeText = typeNames[displayType] or displayType
            print(CDM_PREFIX .. "|cffff8800" .. (entry.name or "Buff") .. " " .. (L["is already being tracked as"] or "is already being tracked as") .. " " .. typeText)
            return
        end
    end

    -- Calculate default Y offset for new bar (stack vertically)
    local rootCfg = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.buffTrackerBar
    local existingCount = #trackedBuffs
    local baseOffsetY = rootCfg and rootCfg.offsetY or 18
    local defaultOffsetY = baseOffsetY - (existingCount * 20)  -- Each bar 20px below previous

    -- Get bar color from spell school (주문 계열별 자동 색상)
    local autoBarColor = GetSpellSchoolColor(entry.spellID or entry.cooldownID)

    -- [REFACTOR] isAura(버프) vs 능력(쿨다운)에 따라 기본 설정 분기
    -- 능력(쿨다운)은 CDM이 자동 제공 → 수동 설정 불필요
    local isAura = entry.isAura or false
    local defaultBarFillMode = "duration"       -- 둘 다 지속시간/쿨다운 표시
    local defaultMaxStacks = 1                  -- CDM이 자동 감지
    local defaultStackDuration = 0              -- dynamicDuration이 자동 감지
    local defaultDynamicDuration = true          -- CDM/API에서 자동 읽기

    -- Create new tracked buff entry
    local newBuff = {
        uid = GenerateUID(),  -- 고유 식별자 (순서 변경에도 불변)
        cooldownID = entry.cooldownID,
        name = entry.name or "Unknown",
        icon = entry.icon or 134400,
        spellID = entry.spellID or 0,
        displayType = displayType or "bar",  -- "bar", "icon", "sound", "text"
        expanded = false,  -- foldable state
        isAura = isAura,   -- [FIX] 유형 정보 저장 (버프 vs 능력)
        settings = {
            -- Common settings
            maxStacks = defaultMaxStacks,
            stackDuration = defaultStackDuration,
            dynamicDuration = defaultDynamicDuration,
            hideWhenZero = true,
            resetOnCombatEnd = false,
            -- Bar mode settings
            barFillMode = defaultBarFillMode,
            durationTickPositions = {},  -- 비율 배열 (예: {0.3} = 30% 팬데믹)
            barColor = autoBarColor,  -- 주문 계열 기반 자동 색상
            bgColor = { 0.15, 0.15, 0.15, 1 },
            showStacksText = false,
            showDurationText = false,
            showTicks = true,
            tickWidth = 2,
            -- Stacks text settings
            textSize = 12,
            textAlign = "CENTER",
            textX = 0,
            textY = 0,
            textColor = { 1, 1, 1, 1 },
            -- Duration text settings
            durationTextSize = 10,
            durationTextAlign = "CENTER",
            durationTextX = 0,
            durationTextY = 0,
            durationTextColor = { 1, 1, 1, 1 },
            offsetX = 0,
            offsetY = defaultOffsetY,
            width = 0,  -- 0 = auto (use global width)
            height = rootCfg and rootCfg.height or 4,
            barOrientation = "HORIZONTAL", -- "HORIZONTAL" or "VERTICAL"
            barReverseFill = false,  -- 바: 역방향 채움
            ringReverse = false,     -- 링: 역방향 (채움 vs 비움)
            -- Icon mode settings
            iconAnimation = "button",
            iconSource = "buff",
            customIconID = 0,
            iconSize = 32,
            iconOffsetX = 0,
            iconOffsetY = 0,
            showIconBorder = true,
            iconBorderSize = 1,
            iconBorderColor = { 0, 0, 0, 1 },
            iconZoom = 0.08,  -- 0 = no crop, 0.08 = default slight crop
            iconAspectRatio = 1.0,  -- 1.0 = square
            iconDesaturate = false,  -- desaturate when not active
            -- Icon stack text settings
            iconShowStackText = true,
            iconStackTextFont = nil,  -- nil = use default
            iconStackTextSize = 12,
            iconStackTextColor = { 1, 1, 1, 1 },
            iconStackTextAnchor = "BOTTOMRIGHT",
            iconStackTextOffsetX = -2,
            iconStackTextOffsetY = 2,
            iconStackTextOutline = "OUTLINE",
            -- Sound mode settings
            soundFile = "None",  -- SharedMedia sound key
            soundCustomPath = "",  -- [12.0.1] custom sound file path (mp3/ogg/wav)
            soundChannel = "Master",  -- Master, SFX, Music, Ambience, Dialog
            soundTrigger = "start",  -- "start", "startDelay", "end", "endBefore", "interval"
            soundStartDelay = 0,  -- seconds after buff starts
            soundEndBefore = 3,  -- seconds before buff ends
            soundInterval = 5,  -- play every X seconds while active
            -- NOTE: soundMinStacks removed - cannot compare secret values in WoW 12.0+
            -- Duration warning settings (지속시간 경고)
            durationWarningEnabled = false,
            durationWarningThreshold = 5,  -- seconds
            durationWarningColor = { 1, 0.2, 0.2, 1 },  -- red
            -- Alert system settings (트리거-액션 알림)
            alerts = {
                enabled = false,
                triggerLogic = "or",
                triggers = {},
                actions = {},
            },
            -- Text mode settings
            textDisplayMode = "stacks",  -- "stacks", "duration", "name", "custom"
            customText = "",
            textAnchor = "CENTER",
            textAnchorTo = "DDingUI_Anchor_Cooldowns", -- [PROXY] 프록시 앵커
            textAnchorPoint = "CENTER",
            textModeOffsetX = 0,
            textModeOffsetY = 50,
            textModeSize = 24,
            textModeFont = nil,
            textModeColor = { 1, 1, 1, 1 },
            textModeOutline = "OUTLINE",
            textShowIcon = true,
            textIconSize = 24,
        }
    }


    -- [SPELL CD] Non-aura spells automatically use spell cooldown mode
    if not isAura and (entry.spellID and entry.spellID > 0) then
        newBuff.trackingMode = "spell"
        -- displaySpellID = 특성 오버라이드/링크 포함 실제 주문 ID
        -- cooldownID = CDM 내부 ID, spellID = base (info.spellID)
        local actualSpellID = entry.displaySpellID or entry.cooldownID or entry.spellID
        newBuff.trigger = {
            type = "spell",
            spellID = actualSpellID,
            cooldownID = entry.cooldownID or 0,
            hideWhenZero = false,
        }
        newBuff.display = newBuff.display or {}
        newBuff.display.barFillMode = "duration"
        -- 텍스트는 사용자가 명시적으로 활성화해야 함 (자동 생성 방지)
        newBuff.display.showDurationText = false
        newBuff.display.showStacksText = false
    end

    -- [TRIGGER] Trigger-only mode: auto-enable alert system
    if displayType == "trigger" then
        newBuff.settings.alerts.enabled = true
        newBuff.settings.hideWhenZero = false
    end

    table.insert(trackedBuffs, newBuff)

    local typeNames = {
        bar = L["Bar"] or "Bar",
        ring = L["Ring"] or "Ring",
        icon = L["Icon"] or "Icon",
        sound = L["Sound"] or "Sound",
        text = L["Text"] or "Text",
        trigger = L["Trigger"] or "Trigger",
    }
    local typeText = typeNames[displayType] or displayType
    print(CDM_PREFIX .. (entry.name or "Buff") .. " " .. (L["added as"] or "added as") .. " " .. typeText)

    -- Update bar first
    if DDingUI.UpdateBuffTrackerBar then
        DDingUI:UpdateBuffTrackerBar()
    end

    -- Refresh options panel (uses SoftRefresh which preserves tab position)
    RefreshOptions()
end

-- Add a spell cooldown tracked buff (no CDM/aura needed - uses C_Spell API directly)
function DDingUI.AddSpellTrackedBuff()
    local trackedBuffs = GetTrackedBuffs()

    local rootCfg = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.buffTrackerBar
    local existingCount = #trackedBuffs
    local baseOffsetY = rootCfg and rootCfg.offsetY or 18
    local defaultOffsetY = baseOffsetY - (existingCount * 20)

    local newBuff = {
        uid = GenerateUID(),
        cooldownID = 0,
        name = (L and L["Spell Cooldown"] or "Spell Cooldown") .. " " .. (#trackedBuffs + 1),
        icon = 134400,
        spellID = 0,
        displayType = "bar",
        expanded = true,
        isAura = false,
        trigger = {
            type = "spell",
            spellID = 0,
            hideWhenZero = false,
        },
        display = {
            type = "bar",
            barFillMode = "duration",
            barColor = { 0.26, 0.78, 1, 1 },
            bgColor = { 0.15, 0.15, 0.15, 1 },
            showStacksText = true,
            showDurationText = true,
            showTicks = true,
            tickWidth = 2,
            textSize = 10,
            textAlign = "LEFT",
            textX = 2,
            textY = 0,
            textColor = { 1, 1, 1, 1 },
            durationTextSize = 10,
            durationTextAlign = "RIGHT",
            durationTextX = -2,
            durationTextY = 0,
            durationTextColor = { 1, 1, 1, 1 },
            durationDecimals = 1,
            width = 0,
            height = rootCfg and rootCfg.height or 4,
            barOrientation = "HORIZONTAL",
            borderSize = 1,
            borderColor = { 0, 0, 0, 1 },
        },
        conditions = {},
        settings = {
            hideWhenZero = false,
            offsetX = 0,
            offsetY = defaultOffsetY,
        },
    }

    table.insert(trackedBuffs, newBuff)

    print(CDM_PREFIX .. (L and L["Spell cooldown tracker added. Set spellID in trigger settings."] or "Spell cooldown tracker added. Set spellID in trigger settings."))

    if DDingUI.UpdateBuffTrackerBar then
        DDingUI:UpdateBuffTrackerBar()
    end
    RefreshOptions()
end

-- Add a manual tracked buff (no CDM entry needed)
local manualBuffCounter = 0
function DDingUI.AddManualTrackedBuff()
    local trackedBuffs = GetTrackedBuffs()

    -- Generate unique cooldownID for manual buffs (negative to avoid collision with CDM)
    manualBuffCounter = manualBuffCounter + 1
    local timestamp = time()
    local uniqueID = -1 * (timestamp * 100 + manualBuffCounter)

    -- Calculate default Y offset for new bar (stack vertically)
    local rootCfg = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.buffTrackerBar
    local existingCount = #trackedBuffs
    local baseOffsetY = rootCfg and rootCfg.offsetY or 18
    local defaultOffsetY = baseOffsetY - (existingCount * 20)

    -- Create new manual tracked buff entry
    local newBuff = {
        cooldownID = uniqueID,
        name = (L["Manual Buff"] or "Manual Buff") .. " " .. (#trackedBuffs + 1),
        icon = 134400,  -- Question mark icon
        spellID = 0,
        displayType = "bar",
        expanded = true,  -- Start expanded so user can configure
        trackingMode = "manual",  -- Key difference: manual tracking mode
        settings = {
            -- Common settings
            maxStacks = 10,
            stackDuration = 30,
            dynamicDuration = true,  -- 기본값: 자동 감지 ON
            hideWhenZero = true,
            resetOnCombatEnd = false,
            -- Manual tracking settings
            generators = {},  -- { { spellID = 12345, stacks = 1 }, ... }
            spenders = {},    -- { { spellID = 67890, consume = 1 }, ... }
            -- Bar mode settings
            barFillMode = "stacks",
            durationTickPositions = {},
            barColor = { 1, 0.8, 0, 1 },
            bgColor = { 0.15, 0.15, 0.15, 1 },
            showStacksText = false,
            showDurationText = false,
            showTicks = true,
            tickWidth = 2,
            -- Stacks text settings
            textSize = 12,
            textAlign = "CENTER",
            textX = 0,
            textY = 0,
            textColor = { 1, 1, 1, 1 },
            -- Duration text settings
            durationTextSize = 10,
            durationTextAlign = "CENTER",
            durationTextX = 0,
            durationTextY = 0,
            durationTextColor = { 1, 1, 1, 1 },
            offsetX = 0,
            offsetY = defaultOffsetY,
            width = 0,
            height = rootCfg and rootCfg.height or 4,
            barOrientation = "HORIZONTAL", -- "HORIZONTAL" or "VERTICAL"
            barReverseFill = false,  -- 바: 역방향 채움
            ringReverse = false,     -- 링: 역방향 (채움 vs 비움)
            -- Icon mode settings
            iconAnimation = "button",
            iconSource = "buff",
            customIconID = 0,
            iconSize = 32,
            iconOffsetX = 0,
            iconOffsetY = 0,
            showIconBorder = true,
            iconBorderSize = 1,
            iconBorderColor = { 0, 0, 0, 1 },
            iconZoom = 0.08,
            iconAspectRatio = 1.0,
            iconDesaturate = false,
            -- Icon stack text settings
            iconShowStackText = true,
            iconStackTextFont = nil,
            iconStackTextSize = 12,
            iconStackTextColor = { 1, 1, 1, 1 },
            iconStackTextAnchor = "BOTTOMRIGHT",
            iconStackTextOffsetX = -2,
            iconStackTextOffsetY = 2,
            iconStackTextOutline = "OUTLINE",
            -- Sound mode settings
            soundFile = "None",
            soundCustomPath = "",  -- [12.0.1] custom sound file path
            soundChannel = "Master",
            soundTrigger = "start",
            soundStartDelay = 0,
            soundEndBefore = 3,
            soundInterval = 5,
            -- Duration warning settings
            durationWarningEnabled = false,
            durationWarningThreshold = 5,
            durationWarningColor = { 1, 0.2, 0.2, 1 },
            -- Alert system settings (트리거-액션 알림)
            alerts = {
                enabled = false,
                triggerLogic = "or",
                triggers = {},
                actions = {},
            },
            -- Text mode settings
            textDisplayMode = "stacks",
            customText = "",
            textAnchor = "CENTER",
            textAnchorTo = "DDingUI_Anchor_Cooldowns", -- [PROXY] 프록시 앵커
            textAnchorPoint = "CENTER",
            textModeOffsetX = 0,
            textModeOffsetY = 50,
            textModeSize = 24,
            textModeFont = nil,
            textModeColor = { 1, 1, 1, 1 },
            textModeOutline = "OUTLINE",
            textShowIcon = true,
            textIconSize = 24,
        }
    }

    table.insert(trackedBuffs, newBuff)

    print(CDM_PREFIX .. (L["Manual tracked buff added. Configure generators/spenders below."] or "Manual tracked buff added. Configure generators/spenders below."))

    -- Update bar
    if DDingUI.UpdateBuffTrackerBar then
        DDingUI:UpdateBuffTrackerBar()
    end

    -- Refresh options panel
    RefreshOptions()
end

-- ============================================================
-- GROUP SYSTEM (WeakAuras-style tracker groups)
-- ============================================================

-- Check if a tracked buff entry is a group
function DDingUI.IsGroupEntry(index)
    local trackedBuffs = GetTrackedBuffs()
    local entry = trackedBuffs[index]
    return entry and entry.isGroup == true
end

-- Get children indices for a group
function DDingUI.GetGroupChildren(groupIdx)
    local trackedBuffs = GetTrackedBuffs()
    local group = trackedBuffs[groupIdx]
    if not group or not group.isGroup then return {} end
    return group.controlledChildren or {}
end

-- Create a new tracker group
function DDingUI.CreateTrackerGroup(name)
    local trackedBuffs = GetTrackedBuffs()

    local newGroup = {
        isGroup = true,
        name = name or ((L["New Group"] or "New Group") .. " " .. (#trackedBuffs + 1)),
        expanded = true,
        controlledChildren = {},
        disabled = false,
        groupSettings = {
            growthDirection = "DOWN",
            growthSpacing = 2,
            sortMode = "none",    -- none / priority / duration / name
            attachTo = DDingUI.db.profile.buffTrackerBar.attachTo or "UIParent",
            anchorPoint = DDingUI.db.profile.buffTrackerBar.anchorPoint or "TOP",
            selfPoint = DDingUI.db.profile.buffTrackerBar.selfPoint or "TOP",
            offsetX = DDingUI.db.profile.buffTrackerBar.offsetX or 0,
            offsetY = DDingUI.db.profile.buffTrackerBar.offsetY or 18,
            frameStrata = DDingUI.db.profile.buffTrackerBar.frameStrata or "MEDIUM",
            -- Load conditions
            loadSpec = {},  -- spec indices that enable this group
            loadCombatOnly = false,
            loadInstanceType = "all",
        },
    }

    table.insert(trackedBuffs, newGroup)
    print(CDM_PREFIX .. (L["New group created:"] or "New group created:") .. " " .. newGroup.name)

    if DDingUI.UpdateBuffTrackerBar then
        DDingUI:UpdateBuffTrackerBar()
    end
    RefreshOptions()
    return #trackedBuffs
end

-- Add tracker to a group
function DDingUI.AddToGroup(trackerIdx, groupIdx)
    local trackedBuffs = GetTrackedBuffs()
    local group = trackedBuffs[groupIdx]
    local tracker = trackedBuffs[trackerIdx]
    if not group or not group.isGroup or not tracker then return end
    if tracker.isGroup then return end  -- can't nest groups

    -- Remove from previous group if any
    if tracker.parentGroup then
        DDingUI.RemoveFromGroup(trackerIdx)
    end

    -- Add to new group
    if not group.controlledChildren then group.controlledChildren = {} end
    table.insert(group.controlledChildren, trackerIdx)
    tracker.parentGroup = groupIdx

    if DDingUI.UpdateBuffTrackerBar then
        DDingUI:UpdateBuffTrackerBar()
    end
    RefreshOptions()
end

-- Remove tracker from its group
function DDingUI.RemoveFromGroup(trackerIdx)
    local trackedBuffs = GetTrackedBuffs()
    local tracker = trackedBuffs[trackerIdx]
    if not tracker or not tracker.parentGroup then return end

    local group = trackedBuffs[tracker.parentGroup]
    if group and group.controlledChildren then
        for i, childIdx in ipairs(group.controlledChildren) do
            if childIdx == trackerIdx then
                table.remove(group.controlledChildren, i)
                break
            end
        end
    end

    tracker.parentGroup = nil

    if DDingUI.UpdateBuffTrackerBar then
        DDingUI:UpdateBuffTrackerBar()
    end
    RefreshOptions()
end

-- Build flat display order (groups then children, skip children of collapsed groups)
function DDingUI.GetDisplayOrder(includeCollapsed)
    local trackedBuffs = GetTrackedBuffs()
    local order = {}
    local childrenInGroups = {}

    -- Collect all children that belong to groups
    for i, entry in ipairs(trackedBuffs) do
        if entry.isGroup and entry.controlledChildren then
            for _, childIdx in ipairs(entry.controlledChildren) do
                childrenInGroups[childIdx] = true
            end
        end
    end

    -- Render: first top-level items (not in any group), preserving order
    for i, entry in ipairs(trackedBuffs) do
        if entry.isGroup then
            -- Group header
            table.insert(order, { index = i, isGroup = true, depth = 0 })
            -- Children (if expanded or includeCollapsed) — nil → 기본 열림
            if (entry.expanded ~= false) or includeCollapsed then
                for _, childIdx in ipairs(entry.controlledChildren or {}) do
                    if trackedBuffs[childIdx] then
                        table.insert(order, { index = childIdx, isGroup = false, depth = 1, parentGroup = i })
                    end
                end
            end
        elseif not childrenInGroups[i] then
            -- Top-level tracker (not in any group)
            table.insert(order, { index = i, isGroup = false, depth = 0 })
        end
    end

    return order
end

-- Create group settings options (for right panel when group is selected)
function DDingUI.CreateGroupOptions(groupIdx)
    local trackedBuffs = GetTrackedBuffs()
    local group = trackedBuffs[groupIdx]
    if not group or not group.isGroup then return {} end

    local gs = group.groupSettings or {}
    local options = {}

    -- ─── Group Name ───
    options["groupName"] = {
        type = "input",
        name = L["Group Name"] or "Group Name",
        order = 0.1,
        width = "double",
        get = function() return group.name or "" end,
        set = function(_, val)
            group.name = val
            RefreshOptions()
        end,
    }
    options["groupEnabled"] = {
        type = "toggle",
        name = L["Enabled"] or "Enabled",
        order = 0.2,
        width = "full",
        get = function() return not group.disabled end,
        set = function(_, val)
            group.disabled = not val
            DDingUI:UpdateBuffTrackerBar()
        end,
    }

    -- ─── Growth / Layout ───
    options["layoutHeader"] = {
        type = "header",
        name = L["Layout"] or "Layout",
        order = 1,
    }
    options["growthDirection"] = {
        type = "select",
        name = L["Growth Direction"] or "Growth Direction",
        order = 1.1, width = "normal",
        values = {
            DOWN = L["Down"] or "Down", UP = L["Up"] or "Up",
            LEFT = L["Left"] or "Left", RIGHT = L["Right"] or "Right",
        },
        get = function() return gs.growthDirection or "DOWN" end,
        set = function(_, val)
            group.groupSettings.growthDirection = val
            DDingUI:UpdateBuffTrackerBar()
        end,
    }
    options["growthSpacing"] = {
        type = "range",
        name = L["Spacing"] or "Spacing",
        order = 1.2, width = "normal",
        min = 0, max = 50, step = 1,
        get = function() return gs.growthSpacing or 2 end,
        set = function(_, val)
            group.groupSettings.growthSpacing = val
            DDingUI:UpdateBuffTrackerBar()
        end,
    }
    options["sortMode"] = {
        type = "select",
        name = L["Sort Mode"] or "Sort Mode",
        desc = L["How children are sorted at runtime"] or "How children are sorted at runtime",
        order = 1.3, width = "normal",
        values = {
            none = L["Manual (drag order)"] or "Manual",
            priority = L["Priority"] or "Priority",
            duration = L["Remaining Duration"] or "Duration",
            name = L["Name"] or "Name",
        },
        get = function() return gs.sortMode or "none" end,
        set = function(_, val)
            group.groupSettings.sortMode = val
            DDingUI:UpdateBuffTrackerBar()
        end,
    }

    -- ─── Position & Anchor ───
    options["positionHeader"] = {
        type = "header",
        name = L["Position & Anchor"] or "Position & Anchor",
        order = 2,
    }
    options["attachTo"] = {
        type = "select",
        name = L["Attach To"] or "Attach To",
        order = 2.1, width = "double",
        values = function()
            local opts = {}
            opts["UIParent"] = L["Screen (UIParent)"] or "Screen (UIParent)"
            if DDingUI.db.profile.unitFrames and DDingUI.db.profile.unitFrames.enabled then
                opts["DDingUI_Player"] = L["Player Frame (Custom)"] or "Player Frame (Custom)"
            end
            opts["PlayerFrame"] = L["Default Player Frame"] or "Default Player Frame"
            return opts
        end,
        get = function() return gs.attachTo or "UIParent" end,
        set = function(_, val)
            group.groupSettings.attachTo = val
            DDingUI:UpdateBuffTrackerBar()
        end,
    }
    options["anchorPoint"] = {
        type = "select",
        name = L["Anchor Point"] or "Anchor Point",
        order = 2.2, width = "normal",
        values = {
            ["TOPLEFT"] = L["Top Left"] or "Top Left",
            ["TOP"] = L["Top"] or "Top",
            ["TOPRIGHT"] = L["Top Right"] or "Top Right",
            ["LEFT"] = L["Left"] or "Left",
            ["CENTER"] = L["Center"] or "Center",
            ["RIGHT"] = L["Right"] or "Right",
            ["BOTTOMLEFT"] = L["Bottom Left"] or "Bottom Left",
            ["BOTTOM"] = L["Bottom"] or "Bottom",
            ["BOTTOMRIGHT"] = L["Bottom Right"] or "Bottom Right",
        },
        get = function() return gs.anchorPoint or "CENTER" end,
        set = function(_, val)
            group.groupSettings.anchorPoint = val
            DDingUI:UpdateBuffTrackerBar()
        end,
    }
    options["selfPoint"] = {
        type = "select",
        name = L["Self Point"] or "Self Point",
        order = 2.3, width = "normal",
        values = {
            ["TOPLEFT"] = L["Top Left"] or "Top Left",
            ["TOP"] = L["Top"] or "Top",
            ["TOPRIGHT"] = L["Top Right"] or "Top Right",
            ["LEFT"] = L["Left"] or "Left",
            ["CENTER"] = L["Center"] or "Center",
            ["RIGHT"] = L["Right"] or "Right",
            ["BOTTOMLEFT"] = L["Bottom Left"] or "Bottom Left",
            ["BOTTOM"] = L["Bottom"] or "Bottom",
            ["BOTTOMRIGHT"] = L["Bottom Right"] or "Bottom Right",
        },
        get = function() return gs.selfPoint or "CENTER" end,
        set = function(_, val)
            group.groupSettings.selfPoint = val
            DDingUI:UpdateBuffTrackerBar()
        end,
    }
    options["offsetX"] = {
        type = "range",
        name = L["X Offset"] or "X Offset",
        order = 2.4, width = "normal",
        min = -500, max = 500, step = 1,
        get = function() return gs.offsetX or 0 end,
        set = function(_, val)
            group.groupSettings.offsetX = val
            DDingUI:UpdateBuffTrackerBar()
        end,
    }
    options["offsetY"] = {
        type = "range",
        name = L["Y Offset"] or "Y Offset",
        order = 2.5, width = "normal",
        min = -500, max = 500, step = 1,
        get = function() return gs.offsetY or 0 end,
        set = function(_, val)
            group.groupSettings.offsetY = val
            DDingUI:UpdateBuffTrackerBar()
        end,
    }
    options["frameStrata"] = {
        type = "select",
        name = L["Frame Strata"] or "Frame Strata",
        order = 2.6, width = "normal",
        values = {
            BACKGROUND = "BACKGROUND", LOW = "LOW", MEDIUM = "MEDIUM", HIGH = "HIGH", DIALOG = "DIALOG",
        },
        get = function() return gs.frameStrata or "MEDIUM" end,
        set = function(_, val)
            group.groupSettings.frameStrata = val
            DDingUI:UpdateBuffTrackerBar()
        end,
    }

    -- ─── Load Conditions ───
    options["loadHeader"] = {
        type = "header",
        name = L["Load Conditions"] or "Load Conditions",
        order = 3,
    }
    options["loadCombatOnly"] = {
        type = "toggle",
        name = L["Combat Only"] or "Combat Only",
        desc = L["Only show this group during combat"] or "Only show this group during combat",
        order = 3.1, width = "full",
        get = function() return gs.loadCombatOnly or false end,
        set = function(_, val)
            group.groupSettings.loadCombatOnly = val
            DDingUI:UpdateBuffTrackerBar()
        end,
    }
    options["loadInstanceType"] = {
        type = "select",
        name = L["Instance Type"] or "Instance Type",
        order = 3.2, width = "normal",
        values = {
            all = L["All"] or "All",
            dungeon = L["Dungeon"] or "Dungeon",
            raid = L["Raid"] or "Raid",
            arena = L["Arena/BG"] or "Arena/BG",
            world = L["Open World"] or "Open World",
        },
        get = function() return gs.loadInstanceType or "all" end,
        set = function(_, val)
            group.groupSettings.loadInstanceType = val
            DDingUI:UpdateBuffTrackerBar()
        end,
    }

    -- ─── Children Management ───
    options["childrenHeader"] = {
        type = "header",
        name = L["Children"] or "Children",
        order = 4,
    }
    local children = group.controlledChildren or {}
    local allTrackedBuffs = GetTrackedBuffs()
    if #children == 0 then
        options["noChildren"] = {
            type = "description",
            name = "|cff888888" .. (L["No children in this group. Right-click a tracker and select 'Move to Group' to add."] or "No children. Right-click a tracker → Move to Group.") .. "|r",
            order = 4.1,
        }
    else
        for ci, childIdx in ipairs(children) do
            local child = allTrackedBuffs[childIdx]
            if child then
                local childName = child.name or "?"
                if child.spellID and child.spellID > 0 then
                    local sn = C_Spell.GetSpellName(child.spellID)
                    if sn then childName = sn end
                end
                options["child" .. ci .. "_name"] = {
                    type = "description",
                    name = "  " .. ci .. ". " .. childName .. "  |cff888888[" .. (child.displayType or "bar"):upper() .. "]|r",
                    order = 4 + ci * 0.1,
                    fontSize = "medium",
                }
            end
        end
    end
    -- ─── Conditional Actions (Action Set 구조) ───
    -- DB 기본값 보장
    if not group.groupSettings.conditionalActions then
        group.groupSettings.conditionalActions = {
            enabled = false,
            sets = {},
        }
    end
    local ca = group.groupSettings.conditionalActions

    -- 마이그레이션: 기존 flat 구조 → sets 구조
    if ca.triggers and not ca.sets then
        ca.sets = {{
            logic = ca.logic or "and",
            triggers = ca.triggers,
            actions = ca.actions or {},
        }}
        ca.triggers = nil
        ca.actions = nil
        ca.logic = nil
    end
    if not ca.sets then ca.sets = {} end

    -- 공용 드롭다운 데이터
    local childValues = {}
    for ci, childIdx in ipairs(children) do
        local child = allTrackedBuffs[childIdx]
        if child then
            local n = child.name or "?"
            if child.spellID and child.spellID > 0 then
                local sn = C_Spell.GetSpellName(child.spellID)
                if sn then n = sn end
            end
            childValues[ci] = ci .. ". " .. n
        end
    end

    local conditionValues = {}
    local CA_MODULE = DDingUI.ConditionalActions
    if CA_MODULE and CA_MODULE.CONDITIONS then
        for _, cond in ipairs(CA_MODULE.CONDITIONS) do
            conditionValues[cond.id] = cond.name
        end
    end

    local actionTypeValues = {}
    local actionTypeNames = {}
    if CA_MODULE and CA_MODULE.ACTION_TYPES then
        for _, at in ipairs(CA_MODULE.ACTION_TYPES) do
            actionTypeValues[at.id] = at.name
            actionTypeNames[at.id] = at.name
        end
    end

    local barTargetValues = {}
    -- 기본 바 대상 (자원바/시전바)
    if CA_MODULE and CA_MODULE.BAR_TARGETS then
        for _, bt in ipairs(CA_MODULE.BAR_TARGETS) do
            barTargetValues[bt.id] = bt.name
        end
    end
    -- BuffTracker 바 대상 추가: 자식 바들
    for ci, childIdx in ipairs(children) do
        local child = allTrackedBuffs[childIdx]
        if child then
            local n = child.name or "?"
            if child.spellID and child.spellID > 0 then
                local sn = C_Spell.GetSpellName(child.spellID)
                if sn then n = sn end
            end
            barTargetValues["bt_child_" .. ci] = "TrackerBar: " .. n
        end
    end

    -- 헤더
    options["actionsHeader"] = {
        type = "description",
        name = "|cffffa300" .. (L["Conditional Actions"] or "Conditional Actions") .. "|r",
        order = 5,
        fontSize = "large",
        width = "full",
    }
    options["actionsEnabled"] = {
        type = "toggle",
        name = L["Enable Actions"] or "Enable Actions",
        order = 5.1, width = "full",
        get = function() return ca.enabled end,
        set = function(_, val) ca.enabled = val; RefreshOptions() end,
    }

    -- ─── 각 Action Set 렌더링 ───
    for si, set in ipairs(ca.sets) do
        local setOrder = 5.2 + si * 0.5
        local setArgs = {}

        -- ── 세트 내 Triggers 섹션 ──
        setArgs["triggersLabel"] = {
            type = "description",
            name = "|cff88ccff" .. (L["Triggers"] or "Triggers") .. "|r",
            order = 1,
            fontSize = "medium",
            width = "full",
        }
        setArgs["triggerLogic"] = {
            type = "select",
            name = L["Trigger Logic"] or "Logic",
            order = 1.1, width = "half",
            values = { ["and"] = "AND", ["or"] = "OR" },
            get = function() return set.logic or "and" end,
            set = function(_, val) set.logic = val end,
        }

        -- 트리거 목록
        for ti, trigger in ipairs(set.triggers or {}) do
            local tOrder = 1.2 + ti * 0.05

            setArgs["t" .. ti .. "_source"] = {
                type = "select",
                name = "#" .. ti .. " " .. (L["Source"] or "Source"),
                order = tOrder, width = "half",
                values = childValues,
                get = function() return trigger.childIndex or 1 end,
                set = function(_, val) trigger.childIndex = val; trigger.source = "child" end,
            }
            setArgs["t" .. ti .. "_cond"] = {
                type = "select",
                name = L["Condition"] or "Condition",
                order = tOrder + 0.01, width = "normal",
                values = conditionValues,
                get = function() return trigger.condition or "active" end,
                set = function(_, val)
                    trigger.condition = val
                    -- [FIX] duration 조건 선택 시 maxDuration 자동 채우기 (툴팁에서 추출)
                    if (val == "duration_gte" or val == "duration_lte") and not trigger.maxDuration then
                        local targetSpellID = nil
                        -- 트리거 대상 버프의 spellID 찾기
                        local childIdx = children[trigger.childIndex or 1]
                        local buff = childIdx and allTrackedBuffs[childIdx]
                        if buff then
                            targetSpellID = buff.spellID
                            if (not targetSpellID or targetSpellID == 0) and buff.cooldownID and buff.cooldownID > 0 then
                                targetSpellID = buff.cooldownID
                            end
                        end
                        if targetSpellID and targetSpellID > 0 then
                            local autoD = DDingUI.ExtractDurationFromTooltip and DDingUI.ExtractDurationFromTooltip(targetSpellID)
                            if autoD and autoD > 0 then
                                trigger.maxDuration = autoD
                            end
                        end
                    end
                    RefreshOptions()
                end,
            }
            setArgs["t" .. ti .. "_value"] = {
                type = "range",
                name = L["Value"] or "Value",
                order = tOrder + 0.02, width = "half",
                min = 0,
                -- [FIX] 커스텀 렌더러(CreateRange)가 함수형 max/step을 지원하지 않음
                -- math.min(함수, 숫자) → 에러 → 이후 위젯(maxDuration) 렌더링 중단
                -- duration 조건에서만 이 위젯이 표시되므로 duration 기준 값 사용
                max = 120,
                step = 0.5,
                get = function() return trigger.value or 0 end,
                set = function(_, val) trigger.value = val end,
                hidden = function()
                    local c = trigger.condition or "active"
                    return c ~= "duration_gte" and c ~= "duration_lte"
                end,
            }
            -- 전체 버프 지속시간 (duration 조건에서만 표시 - 수동 카운트다운용)
            -- 이 값을 설정하면 API 대신 수동으로 지속시간을 추적 (전투 중 secret value 우회)
            -- duration 조건 선택 시 툴팁에서 자동 추출하여 채움 (수동 수정 가능)
            setArgs["t" .. ti .. "_maxDuration"] = {
                type = "input",
                name = L["Buff Total Duration (sec)"] or "전체 버프 지속시간 (초)",
                desc = "수동 카운트다운용 전체 지속시간 (초). 전투 중 시크릿밸류 우회. 0 또는 빈칸 = API 사용.",
                order = tOrder + 0.025, width = "half",
                get = function() return tostring(trigger.maxDuration or "") end,
                set = function(_, val)
                    local num = tonumber(val)
                    trigger.maxDuration = (num and num > 0) and num or nil
                end,
                hidden = function()
                    local c = trigger.condition or "active"
                    return c ~= "duration_gte" and c ~= "duration_lte"
                end,
            }
            local tiCapture = ti
            setArgs["t" .. ti .. "_delete"] = {
                type = "execute",
                name = "|cffff4444X|r",
                order = tOrder + 0.03, width = "half",
                hidden = function() return not set.triggers or #set.triggers <= 1 end,
                func = function()
                    table.remove(set.triggers, tiCapture)
                    RefreshOptions()
                end,
            }
        end

        -- 트리거 추가 버튼
        setArgs["trigger_add"] = {
            type = "execute",
            name = "+ " .. (L["Add Trigger"] or "Add Trigger"),
            order = 1.99, width = "normal",
            func = function()
                if not set.triggers then set.triggers = {} end
                table.insert(set.triggers, {
                    source = "child",
                    childIndex = 1,
                    condition = "active",
                    value = 0,
                })
                RefreshOptions()
            end,
        }

        -- ── 세트 내 Actions 섹션 ──
        setArgs["actionsLabel"] = {
            type = "description",
            name = "\n|cff88ccff" .. (L["Actions"] or "Actions") .. "|r",
            order = 3,
            fontSize = "medium",
            width = "full",
        }

        -- 동작 목록 (flat 위젯, prefix로 구분)
        for ai, action in ipairs(set.actions or {}) do
            local aOrder = 3.1 + ai * 0.1
            local typeName = actionTypeNames[action.type] or action.type or "?"
            local p = "a" .. ai .. "_"  -- prefix

            -- 동작 라벨 (구분선)
            setArgs[p .. "label"] = {
                type = "description",
                name = "|cffcccccc" .. (L["Action"] or "Action") .. " " .. ai .. " (" .. typeName .. ")|r",
                order = aOrder,
                fontSize = "medium",
                width = "full",
            }

            setArgs[p .. "type"] = {
                type = "select",
                name = L["Type"] or "Type",
                order = aOrder + 0.01, width = "normal",
                values = actionTypeValues,
                get = function() return action.type or "bar_color" end,
                set = function(_, val)
                    action.type = val
                    RefreshOptions()
                end,
            }
            setArgs[p .. "target"] = {
                type = "select",
                name = L["Target Bar"] or "Target Bar",
                order = aOrder + 0.02, width = "normal",
                values = barTargetValues,
                get = function() return action.target or "PrimaryPowerBar" end,
                set = function(_, val) action.target = val end,
                hidden = function()
                    return action.type ~= "bar_color" and action.type ~= "bar_glow"
                end,
            }
            setArgs[p .. "color"] = {
                type = "color",
                name = L["Color"] or "Color",
                order = aOrder + 0.03, width = "half",
                hasAlpha = true,
                get = function()
                    local c = action.color or {1, 0.2, 0.2, 1}
                    return c[1], c[2], c[3], c[4] or 1
                end,
                set = function(_, r, g, b, a) action.color = {r, g, b, a} end,
                hidden = function()
                    return action.type ~= "bar_color" and action.type ~= "bar_glow"
                        and action.type ~= "icon_glow" and action.type ~= "show_text"
                end,
            }
            setArgs[p .. "childIndex"] = {
                type = "select",
                name = L["Target Child"] or "Target Child",
                order = aOrder + 0.04, width = "normal",
                values = childValues,
                get = function() return action.childIndex or 1 end,
                set = function(_, val) action.childIndex = val end,
                hidden = function()
                    return action.type ~= "icon_glow" and action.type ~= "icon_change"
                end,
            }
            setArgs[p .. "intensity"] = {
                type = "range",
                name = L["Intensity"] or "Intensity",
                order = aOrder + 0.05, width = "half",
                min = 0.1, max = 2.0, step = 0.1,
                get = function() return action.intensity or 0.6 end,
                set = function(_, val) action.intensity = val end,
                hidden = function() return action.type ~= "bar_glow" end,
            }
            setArgs[p .. "newIcon"] = {
                type = "input",
                name = L["New Icon ID"] or "New Icon ID",
                order = aOrder + 0.051, width = "normal",
                get = function() return tostring(action.newIconID or "") end,
                set = function(_, val) action.newIconID = tonumber(val) or val end,
                hidden = function() return action.type ~= "icon_change" end,
            }
            setArgs[p .. "sound"] = {
                type = "input",
                name = L["Sound File"] or "Sound File",
                order = aOrder + 0.052, width = "double",
                get = function() return action.soundFile or "" end,
                set = function(_, val) action.soundFile = val end,
                hidden = function() return action.type ~= "play_sound" end,
            }
            setArgs[p .. "soundChannel"] = {
                type = "select",
                name = L["Channel"] or "Channel",
                order = aOrder + 0.053, width = "half",
                values = { Master = "Master", SFX = "SFX", Music = "Music", Dialog = "Dialog" },
                get = function() return action.channel or "Master" end,
                set = function(_, val) action.channel = val end,
                hidden = function() return action.type ~= "play_sound" end,
            }
            setArgs[p .. "soundCooldown"] = {
                type = "range",
                name = L["Cooldown"] or "Cooldown (sec)",
                order = aOrder + 0.054, width = "half",
                min = 0, max = 60, step = 1,
                get = function() return action.cooldown or 3 end,
                set = function(_, val) action.cooldown = val end,
                hidden = function() return action.type ~= "play_sound" end,
            }
            setArgs[p .. "text"] = {
                type = "input",
                name = L["Text"] or "Text",
                order = aOrder + 0.055, width = "double",
                get = function() return action.text or "" end,
                set = function(_, val) action.text = val end,
                hidden = function() return action.type ~= "show_text" end,
            }
            setArgs[p .. "textSize"] = {
                type = "range",
                name = L["Size"] or "Size",
                order = aOrder + 0.056, width = "half",
                min = 10, max = 60, step = 1,
                get = function() return action.size or 28 end,
                set = function(_, val) action.size = val end,
                hidden = function() return action.type ~= "show_text" end,
            }
            setArgs[p .. "textDuration"] = {
                type = "range",
                name = L["Duration"] or "Duration (sec)",
                order = aOrder + 0.057, width = "half",
                min = 0.5, max = 10, step = 0.5,
                get = function() return action.duration or 2 end,
                set = function(_, val) action.duration = val end,
                hidden = function() return action.type ~= "show_text" end,
            }
            setArgs[p .. "textPos"] = {
                type = "select",
                name = L["Position"] or "Position",
                order = aOrder + 0.058, width = "half",
                values = { CENTER = "Center", TOP = "Top", BOTTOM = "Bottom" },
                get = function() return action.position or "CENTER" end,
                set = function(_, val) action.position = val end,
                hidden = function() return action.type ~= "show_text" end,
            }

            local aiCapture = ai
            setArgs[p .. "delete"] = {
                type = "execute",
                name = "|cffff4444" .. (L["Delete Action"] or "Delete") .. "|r",
                order = aOrder + 0.09, width = "half",
                hidden = function() return not set.actions or #set.actions <= 1 end,
                func = function()
                    table.remove(set.actions, aiCapture)
                    RefreshOptions()
                end,
            }
        end

        -- 동작 추가 버튼
        setArgs["action_add"] = {
            type = "execute",
            name = "+ " .. (L["Add Action"] or "Add Action"),
            order = 3.99, width = "normal",
            func = function()
                if not set.actions then set.actions = {} end
                table.insert(set.actions, {
                    type = "bar_color",
                    target = "PrimaryPowerBar",
                    color = {1, 0.2, 0.2, 1},
                })
                RefreshOptions()
            end,
        }

        -- 세트 삭제 버튼
        local siCapture = si
        setArgs["deleteSet"] = {
            type = "execute",
            name = "|cffff4444" .. (L["Delete Set"] or "Delete Set") .. "|r",
            order = 99, width = "normal",
            func = function()
                table.remove(ca.sets, siCapture)
                RefreshOptions()
            end,
        }

        -- 세트 제목 (트리거/동작 수 표시)
        local trigCount = set.triggers and #set.triggers or 0
        local actCount = set.actions and #set.actions or 0
        local setName = (L["Action Set"] or "Action Set") .. " " .. si
            .. "  |cff888888(" .. trigCount .. " " .. (L["triggers"] or "triggers")
            .. ", " .. actCount .. " " .. (L["actions"] or "actions") .. ")|r"

        -- 세트를 폴더블 inline group으로 등록
        options["set_" .. si] = {
            type = "group",
            name = setName,
            order = setOrder,
            inline = true,
            args = setArgs,
        }
    end

    -- ─── 동작 세트 추가 버튼 ───
    options["set_add_spacer"] = {
        type = "description",
        name = " ",
        order = 9.98,
        width = "full",
    }
    options["set_add"] = {
        type = "execute",
        name = "|cff44ff44+ " .. (L["Add Action Set"] or "Add Action Set") .. "|r",
        order = 9.99, width = "full",
        func = function()
            table.insert(ca.sets, {
                logic = "and",
                triggers = {
                    { source = "child", childIndex = 1, condition = "active", value = 0 },
                },
                actions = {
                    { type = "bar_color", target = "PrimaryPowerBar", color = {1, 0.2, 0.2, 1} },
                },
            })
            RefreshOptions()
        end,
    }

    return options
end

-- Export group functions
ns.CreateGroupOptions = DDingUI.CreateGroupOptions


-- Confirmation dialog for removal
local confirmDeleteDialog = nil
local pendingDeleteIndex = nil

local function CreateConfirmDeleteDialog()
    if confirmDeleteDialog then return confirmDeleteDialog end

    local GUI = DDingUI.GUI or {}
    local THEME = GUI.THEME or {
        bgMain = {0.10, 0.10, 0.10, 0.95},
        bgWidget = {0.06, 0.06, 0.06, 0.80},
        border = {0.25, 0.25, 0.25, 0.50},
        text = {0.85, 0.85, 0.85, 1},
        accent = {0.90, 0.45, 0.12},
        gold = {0.90, 0.45, 0.12, 1},
        error = {0.90, 0.25, 0.25, 1},
    }
    local StyleFontString = GUI.StyleFontString

    local frame = CreateFrame("Frame", "DDingUI_ConfirmDeleteDialog", UIParent, "BackdropTemplate")
    frame:SetSize(280, 120)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(200)

    frame:SetBackdrop({
        bgFile = FLAT,
        edgeFile = FLAT,
        tile = false,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    frame:SetBackdropColor(THEME.bgMain[1], THEME.bgMain[2], THEME.bgMain[3], 0.98)
    frame:SetBackdropBorderColor(THEME.error[1], THEME.error[2], THEME.error[3], 1)

    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:Hide()

    -- Title bar for dragging
    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetHeight(30)
    titleBar:SetPoint("TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", 0, 0)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)

    -- Title
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    if StyleFontString then StyleFontString(frame.title) end
    frame.title:SetPoint("TOP", 0, -15)
    frame.title:SetText(L["Confirm Delete"] or "Confirm Delete")
    frame.title:SetTextColor(THEME.error[1], THEME.error[2], THEME.error[3], 1)

    -- Message
    frame.message = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    if StyleFontString then StyleFontString(frame.message) end
    frame.message:SetPoint("TOP", frame.title, "BOTTOM", 0, -10)
    frame.message:SetText("")
    frame.message:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3], 1)

    -- Helper to create button
    local function CreateConfirmButton(parent, width, text, isCancel)
        local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
        btn:SetSize(width, 24)
        btn:EnableMouse(true)
        btn:SetFrameLevel(parent:GetFrameLevel() + 10)
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        btn:SetBackdrop({
            bgFile = FLAT,
            edgeFile = FLAT,
            tile = false, edgeSize = 1,
            insets = { left = 0, right = 0, top = 0, bottom = 0 }
        })

        local bgColor = isCancel and THEME.bgWidget or {0.6, 0.15, 0.15, 1}
        btn:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], 1)
        btn:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 1)

        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        if StyleFontString then StyleFontString(label) end
        label:SetPoint("CENTER")
        label:SetText(text)
        label:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3], 1)
        btn.label = label

        btn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.8)
            self.label:SetTextColor(1, 1, 1, 1)
        end)
        btn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], 1)
            self.label:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3], 1)
        end)

        return btn
    end

    -- Delete button
    frame.deleteBtn = CreateConfirmButton(frame, 80, L["Delete"] or "Delete", false)
    frame.deleteBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -10, 15)
    frame.deleteBtn:SetScript("OnClick", function()
        if pendingDeleteIndex then
            DDingUI.DoRemoveTrackedBuff(pendingDeleteIndex)
            pendingDeleteIndex = nil
        end
        frame:Hide()
    end)

    -- Cancel button
    frame.cancelBtn = CreateConfirmButton(frame, 80, L["Cancel"] or "Cancel", true)
    frame.cancelBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOM", 10, 15)
    frame.cancelBtn:SetScript("OnClick", function()
        pendingDeleteIndex = nil
        frame:Hide()
    end)

    tinsert(UISpecialFrames, "DDingUI_ConfirmDeleteDialog")

    confirmDeleteDialog = frame
    return frame
end

-- Show confirmation dialog
function DDingUI.ConfirmRemoveTrackedBuff(index)
    local trackedBuffs = GetTrackedBuffs()
    if not trackedBuffs[index] then return end

    pendingDeleteIndex = index
    local dialog = CreateConfirmDeleteDialog()
    local buffName = trackedBuffs[index].name or "Unknown"
    dialog.message:SetText((L["Remove '%s' from tracking?"] or "Remove '%s' from tracking?"):format(buffName))
    dialog:Show()
    dialog:Raise()
end

-- Actually remove a tracked buff (called after confirmation)
function DDingUI.DoRemoveTrackedBuff(index)
    local trackedBuffs = GetTrackedBuffs()
    if index >= 1 and index <= #trackedBuffs then
        local removed = table.remove(trackedBuffs, index)
        print(CDM_PREFIX .. (removed and removed.name or "Buff") .. " " .. (L["removed from tracking"] or "removed from tracking"))

        -- Immediately hide ALL tracker frames to ensure clean state
        -- This is critical because excess frames must be hidden after removal
        local barFrames = DDingUI:GetTrackedBuffBars()
        local iconFrames = DDingUI:GetTrackedBuffIcons()
        local textFrames = DDingUI:GetTrackedBuffTexts()
        local soundTrackers = DDingUI:GetSoundTrackers()

        if barFrames then
            for _, bar in pairs(barFrames) do
                if bar and bar.Hide then bar:Hide() end
            end
        end
        if iconFrames then
            for _, icon in pairs(iconFrames) do
                if icon and icon.Hide then
                    icon:Hide()
                    -- Also hide glow if present
                    if icon._glowAnimation then
                        local SL = _G.DDingUI_StyleLib
                        if SL then SL.HideAllGlows(icon) end
                        icon._glowAnimation = false
                    end
                end
            end
        end
        if textFrames then
            for _, textFrame in pairs(textFrames) do
                if textFrame and textFrame.Hide then textFrame:Hide() end
            end
        end
        if soundTrackers then
            for barIndex, tracker in pairs(soundTrackers) do
                tracker.wasActive = false
                tracker.lastPlayTime = 0
            end
        end

        -- Now update to re-show only valid trackers
        if DDingUI.UpdateBuffTrackerBar then
            DDingUI:UpdateBuffTrackerBar()
        end

        RefreshOptions()
    end
end

-- Remove a tracked buff by index (shows confirmation)
function DDingUI.RemoveTrackedBuff(index)
    DDingUI.ConfirmRemoveTrackedBuff(index)
end

-- Toggle expanded state for a tracked buff
local function ToggleBuffExpanded(index)
    local trackedBuffs = GetTrackedBuffs()
    if trackedBuffs[index] then
        trackedBuffs[index].expanded = not trackedBuffs[index].expanded
    end
end

-- Check if a buff is expanded
local function IsBuffExpanded(index)
    local trackedBuffs = GetTrackedBuffs()
    return trackedBuffs[index] and trackedBuffs[index].expanded
end

-- Get tracked buff by index
local function GetTrackedBuff(index)
    local trackedBuffs = GetTrackedBuffs()
    return trackedBuffs[index]
end

-- Use shared helper from ConfigHelpers (with fallback)
local function GetViewerOptions()
    if DDingUI.GetViewerOptions then
        return DDingUI:GetViewerOptions()
    end
    -- Fallback: 프록시 앵커 프레임 우선
    return {
        ["DDingUI_Anchor_Cooldowns"] = L["Essential Cooldowns"] or "핵심 능력",
        ["DDingUI_Anchor_Buffs"] = L["Buff Icons"] or "강화 효과",
        ["DDingUI_Anchor_Utility"] = L["Utility Cooldowns"] or "보조 능력",
    }
end

-- Get current specialization ID (unique across all classes)
local function GetCurrentSpecID()
    local specIndex = GetSpecialization()
    if not specIndex then
        return nil
    end
    local specID = GetSpecializationInfo(specIndex)
    return specID
end

-- Get current spec name for display
local function GetCurrentSpecName()
    local specID = GetCurrentSpecID()
    local _, name = GetSpecializationInfo(specID)
    return name or ("Spec " .. specID)
end

-- Use shared default spec config from ConfigHelpers (with fallback for load order safety)
local defaultSpecConfig
if DDingUI.GetBuffTrackerDefaultSpecConfigRef then
    defaultSpecConfig = DDingUI:GetBuffTrackerDefaultSpecConfigRef()
end
if not defaultSpecConfig then
    -- Fallback: define locally if ConfigHelpers not loaded yet
    defaultSpecConfig = {
        maxStacks = 1,
        stackDuration = 20,
        hideWhenZero = true,
        resetOnCombatEnd = true,
        barFillMode = "stacks",
        trackingMode = "cdm",
        cooldownID = 0,
        attachTo = "DDingUI_Anchor_Cooldowns", -- [PROXY] 프록시 앵커 사용
        anchorPoint = "BOTTOM",
        height = 6,
        width = 0,
        offsetX = 0,
        offsetY = -1,
        texture = nil,
        barColor = { 1, 0.8, 0, 1 },
        bgColor = { 0.15, 0.15, 0.15, 1 },
        borderSize = 1,
        borderColor = { 0, 0, 0, 1 },
        showStacksText = false,
        showDurationText = false,
        showTicks = true,
        tickWidth = 2,
        smoothProgress = true,
        textFont = nil,
        textSize = 12,
        textX = 0,
        textY = 0,
        textAlign = "CENTER",
        textColor = { 1, 1, 1, 1 },
        durationTextFont = nil,
        durationTextSize = 10,
        durationTextX = 0,
        durationTextY = -10,
        durationTextAlign = "CENTER",
        durationTextColor = { 1, 1, 1, 1 },
        requireTalentID = 0,
        bonusTalentID = 0,
        bonusTalentStacks = 1,
        generators = {},
        spenders = {},
    }
end

-- Get the config table (uses new SpecProfiles system for per-spec handling)
local function GetSpecConfig()
    local rootCfg = DDingUI.db.profile.buffTrackerBar
    return rootCfg, rootCfg
end

-- Get spell name for display
local function GetSpellNameByID(spellID)
    if not spellID or spellID == 0 then return "" end

    -- Try to get spell name
    local name = C_Spell.GetSpellName(spellID)

    -- If name not available, request spell data to be loaded (no auto-refresh to prevent UI flickering)
    if not name or name == "" then
        if C_Spell.RequestLoadSpellData then
            C_Spell.RequestLoadSpellData(spellID)
        end
    end

    return name or ""
end

-- Get spell icon texture for display
local function GetSpellIconByID(spellID)
    if not spellID or spellID == 0 then return nil end
    return C_Spell.GetSpellTexture(spellID)
end

-- ============================================================
-- CDM CATALOG INTEGRATION
-- CDM 프레임에서 실시간으로 오라 목록을 가져옴 (하드코딩 제거)
-- Uses auraInstanceID + C_UnitAuras.GetAuraDataByAuraInstanceID() for accurate tracking
-- ============================================================

-- CDM 카탈로그에서 사용 가능한 오라 목록 가져오기
local function GetAvailableCDMAuras()
    local CDMScanner = DDingUI.CDMScanner
    if not CDMScanner then return {} end

    local entries = CDMScanner.GetAllEntries()
    return entries or {}
end

-- CDM 엔트리로 트래커 설정 (cooldownID 기반 - 가장 정확한 방식!)
local function ApplyCDMEntry(entry)
    if not entry or not entry.cooldownID then return end

    local cfg = GetSpecConfig()
    if not cfg then return end

    -- CDM 추적 모드로 설정
    cfg.trackingMode = "cdm"
    cfg.cooldownID = entry.cooldownID
    cfg.spellID = entry.spellID or 0

    -- 스택/지속시간 설정 (CDM은 실시간으로 가져오므로 기본값만 설정)
    cfg.maxStacks = 10  -- CDM에서 실제 값 가져옴
    cfg.stackDuration = 30  -- CDM에서 실제 값 가져옴
    cfg.dynamicDuration = true  -- 기본값: 자동 감지 ON
    cfg.hideWhenZero = true
    cfg.resetOnCombatEnd = false  -- CDM이 관리하므로 불필요

    -- Manual/Buff 모드용 배열 초기화 (사용 안 함)
    cfg.generators = {}
    cfg.spenders = {}

    -- 바 업데이트
    if DDingUI.UpdateBuffTrackerBar then
        DDingUI:UpdateBuffTrackerBar()
    end

    RefreshOptions()

    local spellName = entry.name or ("ID:" .. entry.cooldownID)
    print(CDM_PREFIX .. spellName .. " (CDM) 설정 적용됨")
end

-- CDM 아이콘 그리드 프레임 (수동 배치)
local cdmIconGridFrame = nil
local cdmIconButtons = {}

local function CreateCDMIconGrid(parent)
    if cdmIconGridFrame then
        cdmIconGridFrame:Show()
        return cdmIconGridFrame
    end

    local ICON_SIZE = 36
    local ICON_SPACING = 4
    local ICONS_PER_ROW = 8
    local MAX_ICONS = 20

    cdmIconGridFrame = CreateFrame("Frame", "DDingUICDMIconGrid", parent)
    cdmIconGridFrame:SetSize(ICONS_PER_ROW * (ICON_SIZE + ICON_SPACING), 3 * (ICON_SIZE + ICON_SPACING))

    for i = 1, MAX_ICONS do
        local row = math.floor((i - 1) / ICONS_PER_ROW)
        local col = (i - 1) % ICONS_PER_ROW

        local btn = CreateFrame("Button", nil, cdmIconGridFrame)
        btn:SetSize(ICON_SIZE, ICON_SIZE)
        btn:SetPoint("TOPLEFT", col * (ICON_SIZE + ICON_SPACING), -row * (ICON_SIZE + ICON_SPACING))

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        btn.icon = icon

        btn:SetScript("OnClick", function(self)
            if self.entry then
                if DDingUI._pendingReplaceIndex then
                    local replaceIdx = DDingUI._pendingReplaceIndex
                    DDingUI._pendingReplaceIndex = nil
                    local trackedBuffs = GetTrackedBuffs()
                    if trackedBuffs[replaceIdx] then
                        local entry = self.entry
                        trackedBuffs[replaceIdx].spellID = entry.spellID or 0
                        trackedBuffs[replaceIdx].cooldownID = entry.cooldownID or trackedBuffs[replaceIdx].cooldownID
                        trackedBuffs[replaceIdx].name = entry.name or trackedBuffs[replaceIdx].name
                        trackedBuffs[replaceIdx].icon = entry.icon or trackedBuffs[replaceIdx].icon
                        if trackedBuffs[replaceIdx].trigger then
                            trackedBuffs[replaceIdx].trigger.spellID = entry.spellID or 0
                        end
                        DDingUI:UpdateBuffTrackerBar()
                        C_Timer.After(0, function()
                            local configFrame = _G["DDingUI_ConfigFrame"]
                            local btPanel = configFrame and configFrame.contentArea and configFrame.contentArea._btPanel
                            if btPanel then
                                if btPanel.RefreshList then btPanel:RefreshList() end
                                if btPanel.SelectTracker then btPanel:SelectTracker(replaceIdx) end
                            end
                        end)
                        print("|cffffffffDDing|r|cffffa300UI|r: |cff00ff00" .. (entry.name or "Spell") .. "|r 으로 주문이 변경되었습니다.")
                    end
                else
                    ShowAddTrackedBuffDialog(self.entry)
                end
            end
        end)

        btn:SetScript("OnEnter", function(self)
            if self.entry then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(self.entry.name or "Unknown", 1, 0.82, 0)
                GameTooltip:AddLine("cooldownID: " .. (self.entry.cooldownID or 0), 0.5, 0.5, 0.5)
                GameTooltip:AddLine("Click to add", 0, 1, 0)
                GameTooltip:Show()
            end
        end)

        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        btn:Hide()
        cdmIconButtons[i] = btn
    end

    return cdmIconGridFrame
end

-- [REMOVED] 이전 UpdateCDMIconGrid → CreateCDMIconGridWidget 내부로 이동됨

-- CDM 카탈로그 옵션
local function CreateCDMCatalogSlotOptions(baseOrder)
    local options = {}

    -- 커스텀 아이콘 그리드 위젯 (GUI.lua에서 특별 처리)
    options["cdmIconGrid"] = {
        type = "embedCDMIconGrid",
        name = "CDM Icon Grid",
        order = baseOrder,
        width = "full",
    }

    return options
end

-- CDM 아이콘 그리드 생성 함수 (GUI.lua에서 호출)
-- [REFACTOR] 핵심/보조/강화 3섹션으로 분류 표시
function DDingUI.CreateCDMIconGridWidget(parent)
    -- 이미 있으면 재사용
    if cdmIconGridFrame then
        cdmIconGridFrame:SetParent(parent)
        cdmIconGridFrame:ClearAllPoints()
        cdmIconGridFrame:Show()
        DDingUI.UpdateCDMIconGrid()
        return cdmIconGridFrame
    end

    local ICON_SIZE = 36
    local ICON_SPACING = 4
    local ICONS_PER_ROW = 8
    local MAX_ICONS_PER_SECTION = 16
    local HEADER_HEIGHT = 18
    local SECTION_SPACING = 8

    local GUI = DDingUI.GUI or {}
    local THEME = GUI.THEME or {
        text = {0.85, 0.85, 0.85, 1},
        accent = {0.90, 0.45, 0.12},
        gold = {0.90, 0.45, 0.12, 1},
        bgWidget = {0.06, 0.06, 0.06, 0.80},
        border = {0.25, 0.25, 0.25, 0.50},
    }
    local StyleFontString = GUI.StyleFontString

    cdmIconGridFrame = CreateFrame("Frame", "DDingUICDMIconGrid", parent)

    -- 카테고리 색상
    local CAT_COLORS = {
        Essential = {0.2, 0.8, 1.0},      -- 파랑 (핵심)
        Utility   = {0.2, 1.0, 0.5},      -- 초록 (보조)
        Buff      = {1.0, 0.75, 0.2},     -- 주황 (강화)
    }
    local CAT_LABELS = {
        Essential = L["Essential Cooldowns"] or "핵심 능력",
        Utility   = L["Utility Cooldowns"] or "보조 능력",
        Buff      = L["Tracked Buffs"] or "강화 효과",
    }
    local CAT_ORDER = { "Buff", "Essential", "Utility" }

    -- 섹션별 프레임 저장
    cdmIconGridFrame._sections = {}
    cdmIconGridFrame._allButtons = {}

    local gridWidth = ICONS_PER_ROW * (ICON_SIZE + ICON_SPACING) - ICON_SPACING

    for _, catKey in ipairs(CAT_ORDER) do
        local section = CreateFrame("Frame", nil, cdmIconGridFrame)
        section:SetWidth(gridWidth)

        -- 카테고리 헤더
        local header = section:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        if StyleFontString then StyleFontString(header) end
        header:SetPoint("TOPLEFT", 0, 0)
        local c = CAT_COLORS[catKey]
        header:SetTextColor(c[1], c[2], c[3], 1)
        header:SetText(CAT_LABELS[catKey])
        section._header = header

        -- 구분선
        local line = section:CreateTexture(nil, "ARTWORK")
        line:SetHeight(1)
        line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
        line:SetPoint("RIGHT", section, "RIGHT", 0, 0)
        line:SetColorTexture(c[1], c[2], c[3], 0.3)
        section._line = line

        -- 빈 문구
        local emptyText = section:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        if StyleFontString then StyleFontString(emptyText) end
        emptyText:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 4, -4)
        emptyText:SetTextColor(0.5, 0.5, 0.5, 1)
        emptyText:SetText("|cff666666(없음)|r")
        emptyText:Hide()
        section._emptyText = emptyText

        -- 아이콘 버튼들
        section._buttons = {}
        for i = 1, MAX_ICONS_PER_SECTION do
            local row = math.floor((i - 1) / ICONS_PER_ROW)
            local col = (i - 1) % ICONS_PER_ROW

            local btn = CreateFrame("Button", nil, section, "BackdropTemplate")
            btn:SetSize(ICON_SIZE, ICON_SIZE)
            btn:SetPoint("TOPLEFT", col * (ICON_SIZE + ICON_SPACING), -(HEADER_HEIGHT + 4) - row * (ICON_SIZE + ICON_SPACING))

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

            btn:SetScript("OnEnter", function(self)
                self:SetBackdropBorderColor(c[1], c[2], c[3], 1)
                if self.entry then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(self.entry.name or "Unknown", 1, 0.82, 0)
                    GameTooltip:AddLine("|cff888888" .. (CAT_LABELS[catKey] or catKey) .. "|r")
                    GameTooltip:AddLine(" ")
                    if self.entry.isAura then
                        GameTooltip:AddLine("유형: 강화 효과 (버프/디버프)", 0.7, 0.7, 0.7)
                    else
                        GameTooltip:AddLine("유형: 능력 (재사용 대기)", 0.7, 0.7, 0.7)
                    end
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine(L["Click to add to tracking"] or "Click to add to tracking", 0, 1, 0)
                    GameTooltip:Show()
                end
            end)

            btn:SetScript("OnLeave", function(self)
                self:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
                GameTooltip:Hide()
            end)

            btn:SetScript("OnClick", function(self)
                if self.entry then
                    -- 교체 모드: 기존 트래커의 주문을 변경
                    if DDingUI._pendingReplaceIndex then
                        local replaceIdx = DDingUI._pendingReplaceIndex
                        DDingUI._pendingReplaceIndex = nil
                        local trackedBuffs = GetTrackedBuffs()
                        if trackedBuffs[replaceIdx] then
                            local entry = self.entry
                            trackedBuffs[replaceIdx].spellID = entry.spellID or 0
                            trackedBuffs[replaceIdx].cooldownID = entry.cooldownID or trackedBuffs[replaceIdx].cooldownID
                            trackedBuffs[replaceIdx].name = entry.name or trackedBuffs[replaceIdx].name
                            trackedBuffs[replaceIdx].icon = entry.icon or trackedBuffs[replaceIdx].icon
                            if trackedBuffs[replaceIdx].trigger then
                                trackedBuffs[replaceIdx].trigger.spellID = entry.spellID or 0
                            end
                            DDingUI:UpdateBuffTrackerBar()
                            -- 리스트 + 설정 패널 갱신
                            C_Timer.After(0, function()
                                local configFrame = _G["DDingUI_ConfigFrame"]
                                local btPanel = configFrame and configFrame.contentArea and configFrame.contentArea._btPanel
                                if btPanel then
                                    if btPanel.RefreshList then btPanel:RefreshList() end
                                    if btPanel.selectedIndex == replaceIdx and btPanel.RenderTrackerTabs then
                                        btPanel:RenderTrackerTabs(replaceIdx)
                                    end
                                    -- 교체 후 해당 트래커를 선택 상태로
                                    if btPanel.SelectTracker then btPanel:SelectTracker(replaceIdx) end
                                end
                            end)
                            print("|cffffffffDDing|r|cffffa300UI|r: |cff00ff00" .. (entry.name or "Spell") .. "|r 으로 주문이 변경되었습니다.")
                        end
                    else
                        ShowAddTrackedBuffDialog(self.entry)
                    end
                end
            end)

            btn:Hide()
            section._buttons[i] = btn
            table.insert(cdmIconGridFrame._allButtons, btn)
        end

        cdmIconGridFrame._sections[catKey] = section
    end

    DDingUI.UpdateCDMIconGrid()
    return cdmIconGridFrame
end

-- CDM 아이콘 그리드 업데이트 (카테고리별 배치)
function DDingUI.UpdateCDMIconGrid()
    if not cdmIconGridFrame or not cdmIconGridFrame._sections then return end

    local CDMScanner = DDingUI.CDMScanner
    if not CDMScanner or not CDMScanner.GetEntriesByCategory then return end

    local grouped = CDMScanner.GetEntriesByCategory()
    local CAT_ORDER = { "Buff", "Essential", "Utility" }

    local ICON_SIZE = 36
    local ICON_SPACING = 4
    local ICONS_PER_ROW = 8
    local HEADER_HEIGHT = 18
    local SECTION_SPACING = 10

    local gridWidth = ICONS_PER_ROW * (ICON_SIZE + ICON_SPACING) - ICON_SPACING
    local yOffset = 0

    for _, catKey in ipairs(CAT_ORDER) do
        local section = cdmIconGridFrame._sections[catKey]
        if not section then break end

        local entries = grouped[catKey] or {}

        section:ClearAllPoints()
        section:SetPoint("TOPLEFT", cdmIconGridFrame, "TOPLEFT", 0, -yOffset)

        -- 버튼 업데이트
        for i, btn in ipairs(section._buttons) do
            local entry = entries[i]
            if entry then
                btn.icon:SetTexture(entry.icon or 134400)
                btn.entry = entry
                btn:Show()
            else
                btn:Hide()
            end
        end

        -- 높이 계산
        local numEntries = #entries
        local numRows = (numEntries > 0) and math.ceil(numEntries / ICONS_PER_ROW) or 0
        local iconsHeight = numRows * (ICON_SIZE + ICON_SPACING)
        local sectionHeight

        if numEntries == 0 then
            section._emptyText:Show()
            sectionHeight = HEADER_HEIGHT + 20
        else
            section._emptyText:Hide()
            sectionHeight = HEADER_HEIGHT + 4 + iconsHeight
        end

        section:SetHeight(sectionHeight)
        section:Show()

        yOffset = yOffset + sectionHeight + SECTION_SPACING
    end

    -- 총 높이 설정
    cdmIconGridFrame:SetWidth(gridWidth)
    cdmIconGridFrame:SetHeight(math.max(40, yOffset))
end

-- CDM 아이콘 그리드 높이 반환 (GUI.lua에서 레이아웃 계산용)
function DDingUI.GetCDMIconGridHeight()
    if cdmIconGridFrame then
        return cdmIconGridFrame:GetHeight() + 10
    end
    -- 기본값: 3섹션 기본 높이
    return 200
end

-- ============================================================
-- TRACKED BUFFS FOLDABLE LIST OPTIONS
-- ============================================================

-- Create a single tracked buff entry options (foldable with detail settings)
local function CreateTrackedBuffOptions(index, baseOrder, skipCollapsible)
    -- baseOrder는 이미 호출 시 index별로 계산되어 전달됨
    -- skipCollapsible: true면 header/remove/spacer 제외, 항상 expanded (커스텀 패널용)
    local orderBase = baseOrder  -- 20 slots per entry (already calculated in caller)
    local options = {}

    -- Hidden function - only show if this index exists
    local function hiddenIfNotExists()
        local trackedBuffs = GetTrackedBuffs()
        return not trackedBuffs[index]
    end

    -- skipCollapsible: 커스텀 패널에서는 header/remove/spacer 불필요 → 건너뜀
    if not skipCollapsible then
        -- Foldable header row: ▶/▼ Name [Type] [X]
        options["tracked" .. index .. "_header"] = {
            type = "execute",
            name = function()
                local buff = GetTrackedBuff(index)
                if not buff then return "" end
                local isEnabled = buff.enabled ~= false
                local arrow = buff.expanded and "▼ " or "▶ "
                local icon = buff.icon and string.format("|T%d:16:16:0:0|t ", buff.icon) or ""
                local typeColors = {
                    bar = "|cff88ff88[Bar]|r",
                    ring = "|cff00ffff[Ring]|r",
                    icon = "|cff8888ff[Icon]|r",
                    sound = "|cffffaa00[Sound]|r",
                    text = "|cffff88ff[Text]|r",
                    trigger = "|cffff6666[Trigger]|r",
                }
                local displayType = typeColors[buff.displayType] or "|cffaaaaaa[Unknown]|r"
                local name = buff.name or "Unknown"
                if not isEnabled then
                    return "|cff666666" .. arrow .. icon .. name .. " " .. displayType .. "|r"
                end
                return arrow .. icon .. name .. " " .. displayType
            end,
            desc = function()
                local buff = GetTrackedBuff(index)
                if not buff then return "" end
                return (L["Click to expand/collapse settings"] or "Click to expand/collapse settings") .. "\ncooldownID: " .. (buff.cooldownID or 0)
            end,
            order = orderBase,
            width = 1.25,
            hidden = hiddenIfNotExists,
            func = function()
                ToggleBuffExpanded(index)
                RefreshOptions()  -- preserveTab = true
            end,
        }

        -- Remove button (오른쪽에 표시)
        options["tracked" .. index .. "_remove"] = {
            type = "execute",
            name = "|cffff4444X|r",
            desc = L["Remove from tracking"] or "Remove from tracking",
            order = orderBase + 0.1,
            width = 0.25,
            hidden = hiddenIfNotExists,
            func = function()
                DDingUI.RemoveTrackedBuff(index)
            end,
        }
    end

    -- Detail settings: skipCollapsible이면 항상 펼침 (expanded)
    local function hiddenIfCollapsed()
        if skipCollapsible then return hiddenIfNotExists() end
        return hiddenIfNotExists() or not IsBuffExpanded(index)
    end

    -- ============================================================
    -- TRACKED SPELL INFO (order 0.3 ~ 0.45)
    -- 추적 중인 주문 정보 표시 + 변경
    -- ============================================================

    -- Tracked spell info display (read-only description)
    options["tracked" .. index .. "_spellInfo"] = {
        type = "description",
        name = function()
            local buff = GetTrackedBuff(index)
            if not buff then return "" end
            local spellID = buff.spellID or (buff.trigger and buff.trigger.spellID) or 0
            local cdID = buff.cooldownID or (buff.trigger and buff.trigger.cooldownID) or ""
            local mode = buff.trackingMode or "auto"
            if buff.trigger and buff.trigger.type == "spell" then mode = "spell" end

            local spellName = ""
            if spellID and spellID > 0 then
                local ok, name = pcall(C_Spell.GetSpellName, spellID)
                if ok and name and name ~= "" then spellName = name end
            end

            local parts = {}
            -- 모드 표시
            local modeLabels = {
                auto = "|cff88ff88" .. (L["Auto (Aura)"] or "Auto") .. "|r",
                manual = "|cffffaa00" .. (L["Manual (Spell)"] or "Manual") .. "|r",
                spell = "|cff00ccff" .. (L["Spell Cooldown"] or "Spell CD") .. "|r",
                cdm = "|cff44ddff CDM|r",
            }
            parts[#parts + 1] = "|cffaaaaaa" .. (L["Mode"] or "Mode") .. ":|r " .. (modeLabels[mode] or mode)

            -- 주문 정보
            if spellName ~= "" then
                parts[#parts + 1] = "|cffaaaaaa" .. (L["Spell"] or "Spell") .. ":|r |cffffffff" .. spellName .. "|r |cff666666(ID: " .. spellID .. ")|r"
            elseif spellID and spellID > 0 then
                parts[#parts + 1] = "|cffaaaaaa Spell ID:|r |cffffffff" .. spellID .. "|r"
            end
            if cdID ~= "" and cdID ~= 0 then
                parts[#parts + 1] = "|cffaaaaaa CDM ID:|r |cff44ddff" .. tostring(cdID) .. "|r"
            end

            if #parts == 0 then
                return "|cff666666" .. (L["No spell assigned"] or "No spell assigned") .. "|r"
            end
            return "    " .. table.concat(parts, "\n    ")
        end,
        order = orderBase + 0.3,
        width = "full",
        fontSize = "medium",
        hidden = hiddenIfCollapsed,
    }

    -- Spell ID input for changing tracked spell
    options["tracked" .. index .. "_changeSpellID"] = {
        type = "input",
        name = "    " .. (L["Change Spell"] or "Change Spell"),
        desc = (L["Enter a new Spell ID to change the tracked spell. The name and icon will be updated automatically."] or "Enter a new Spell ID to change the tracked spell. The name and icon will be updated automatically."),
        order = orderBase + 0.35,
        width = 1.0,
        hidden = function()
            local buff = GetTrackedBuff(index)
            if not buff then return true end
            local isHidden = false
            if skipCollapsible then
                isHidden = hiddenIfNotExists()
            else
                isHidden = hiddenIfNotExists() or not IsBuffExpanded(index)
            end
            if isHidden then return true end
            
            local mode = buff.trackingMode or "auto"
            return mode ~= "auto"
        end,
        get = function()
            local buff = GetTrackedBuff(index)
            if not buff then return "" end
            local spellID = buff.spellID or (buff.trigger and buff.trigger.spellID) or 0
            if spellID == 0 then return "" end
            return tostring(spellID)
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if not trackedBuffs[index] then return end
            local newSpellID = tonumber(val)
            if not newSpellID or newSpellID <= 0 then return end

            -- Update spellID
            trackedBuffs[index].spellID = newSpellID
            if trackedBuffs[index].trigger then
                trackedBuffs[index].trigger.spellID = newSpellID
            end

            -- Auto-update name and icon from spell info
            local ok, spellName = pcall(C_Spell.GetSpellName, newSpellID)
            if ok and spellName and spellName ~= "" then
                trackedBuffs[index].name = spellName
            end
            local iconOk, iconTex = pcall(C_Spell.GetSpellTexture, newSpellID)
            if iconOk and iconTex then
                trackedBuffs[index].icon = iconTex
            end

            DDingUI:UpdateBuffTrackerBar()
            RefreshOptions()
            -- 왼쪽 리스트(이름/아이콘) 즉시 갱신
            C_Timer.After(0, function()
                local configFrame = _G["DDingUI_ConfigFrame"]
                local btPanel = configFrame and configFrame.contentArea and configFrame.contentArea._btPanel
                if btPanel and btPanel.RefreshList then
                    btPanel:RefreshList()
                end
            end)
        end,
    }

    -- Open Catalog Button
    options["tracked" .. index .. "_openCatalog"] = {
        type = "execute",
        name = L["Select from Catalog"] or "Select from Catalog",
        desc = L["Go to CDM Catalog to select auras"] or "Go to CDM Catalog to select auras",
        order = orderBase + 0.36,
        width = 1.0,
        hidden = function()
            local buff = GetTrackedBuff(index)
            if not buff then return true end
            local isHidden = false
            if skipCollapsible then
                isHidden = hiddenIfNotExists()
            else
                isHidden = hiddenIfNotExists() or not IsBuffExpanded(index)
            end
            if isHidden then return true end
            
            local mode = buff.trackingMode or "auto"
            return mode ~= "auto"
        end,
        func = function()
            if DDingUI.OpenAuraCatalog then
                -- 교체 모드로 카탈로그 열기: 현재 인덱스 전달
                DDingUI._pendingReplaceIndex = index
                DDingUI.OpenAuraCatalog()
            end
        end,
    }


    -- Enable/Disable toggle (per-buff)
    options["tracked" .. index .. "_enabled"] = {
        type = "toggle",
        name = "    " .. (L["Enable"] or "Enable"),
        desc = "Enable/Disable this tracked buff",
        order = orderBase + 0.5,
        width = 0.7,
        hidden = hiddenIfCollapsed,
        get = function()
            local buff = GetTrackedBuff(index)
            return not buff or buff.enabled ~= false
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] then
                trackedBuffs[index].enabled = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Display Type
    options["tracked" .. index .. "_displayType"] = {
        type = "select",
        name = "    " .. (L["Display Type"] or "Display Type"),
        order = orderBase + 1,
        width = 0.7,
        hidden = hiddenIfCollapsed,
        values = {
            bar = L["Bar"] or "Bar",
            ring = L["Ring"] or "Ring",
            icon = L["Icon"] or "Icon",
            sound = L["Sound"] or "Sound",
            text = L["Text"] or "Text",
            trigger = L["Trigger Only"] or "Trigger Only",
        },
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.displayType or "bar"
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] then
                trackedBuffs[index].displayType = val
                DDingUI:UpdateBuffTrackerBar()
                RefreshOptions()
            end
        end,
    }

    -- Frame Strata (per-buff override)
    options["tracked" .. index .. "_frameStrata"] = {
        type = "select",
        name = "    " .. (L["Frame Strata"] or "Frame Strata"),
        desc = L["Controls the drawing layer of this bar. Higher strata appear on top of lower ones."] or "Controls the drawing layer of this bar. Higher strata appear on top of lower ones.",
        order = orderBase + 1.05,
        width = 0.7,
        hidden = hiddenIfCollapsed,
        values = {
            DEFAULT = L["Use Global Setting"] or "Use Global Setting",
            BACKGROUND = "BACKGROUND",
            LOW = "LOW",
            MEDIUM = "MEDIUM",
            HIGH = "HIGH",
            DIALOG = "DIALOG",
        },
        sorting = { "DEFAULT", "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG" },
        get = function()
            local buff = GetTrackedBuff(index)
            if buff and buff.settings and buff.settings.frameStrata then
                return buff.settings.frameStrata
            end
            return "DEFAULT"
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] then
                if not trackedBuffs[index].settings then
                    trackedBuffs[index].settings = {}
                end
                if val == "DEFAULT" then
                    trackedBuffs[index].settings.frameStrata = nil
                else
                    trackedBuffs[index].settings.frameStrata = val
                end
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Helper: Hide when not icon mode
    local function hiddenIfNotIcon()
        if hiddenIfCollapsed() then return true end
        local buff = GetTrackedBuff(index)
        return not buff or buff.displayType ~= "icon"
    end

    -- Helper: Hide when not bar mode
    local function hiddenIfNotBar()
        if hiddenIfCollapsed() then return true end
        local buff = GetTrackedBuff(index)
        return not buff or buff.displayType ~= "bar"
    end

    -- Helper: Hide when not duration mode (for duration-specific options)
    local function hiddenIfNotDuration()
        if hiddenIfNotBar() then return true end
        local buff = GetTrackedBuff(index)
        if not buff or not buff.settings then return true end
        -- [FIX] barFillMode가 nil(미설정)이면 기본값 "duration"으로 간주
        local mode = buff.settings.barFillMode or "duration"
        return mode ~= "duration"
    end

    -- Helper: Hide when not sound mode
    local function hiddenIfNotSound()
        if hiddenIfCollapsed() then return true end
        local buff = GetTrackedBuff(index)
        return not buff or buff.displayType ~= "sound"
    end

    -- Helper: Hide when not text mode
    local function hiddenIfNotText()
        if hiddenIfCollapsed() then return true end
        local buff = GetTrackedBuff(index)
        return not buff or buff.displayType ~= "text"
    end

    -- Helper: Hide when not ring mode
    local function hiddenIfNotRing()
        if hiddenIfCollapsed() then return true end
        local buff = GetTrackedBuff(index)
        return not buff or buff.displayType ~= "ring"
    end

    -- Helper: Hide when not manual tracking mode
    local function hiddenIfNotManual()
        if hiddenIfCollapsed() then return true end
        local buff = GetTrackedBuff(index)
        return not buff or buff.trackingMode ~= "manual"
    end

    -- Helper: Hide when not spell tracking mode
    local function hiddenIfNotSpell()
        if hiddenIfCollapsed() then return true end
        local buff = GetTrackedBuff(index)
        if not buff then return true end
        if buff.trigger and buff.trigger.type == "spell" then return false end
        return buff.trackingMode ~= "spell"
    end

    -- ============================================================
    -- TRACKING MODE OPTIONS (order 0.5 ~ 0.9)
    -- ============================================================

    -- Tracking Mode Selector
    options["tracked" .. index .. "_trackingMode"] = {
        type = "select",
        name = "    " .. (L["Tracking Mode"] or "Tracking Mode"),
        desc = L["Auto: Track by buff/aura. Manual: Track by spell casts."] or "Auto: Track by buff/aura. Manual: Track by spell casts.",
        order = orderBase + 0.5,
        width = 0.7,
        hidden = hiddenIfCollapsed,
        values = {
            auto = L["Auto (Aura)"] or "Auto (Aura)",
            manual = L["Manual (Spell)"] or "Manual (Spell)",
            spell = L["Spell Cooldown"] or "Spell Cooldown",
        },
        get = function()
            local buff = GetTrackedBuff(index)
            if not buff then return "auto" end
            if buff.trigger and buff.trigger.type == "spell" then return "spell" end
            return buff.trackingMode or "auto"
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] then
                trackedBuffs[index].trackingMode = val
                -- Clear spell trigger when switching away from spell mode
                if val ~= "spell" and trackedBuffs[index].trigger then
                    trackedBuffs[index].trigger.type = nil
                end
                -- Initialize settings and generators/spenders if switching to manual
                if val == "manual" then
                    -- Ensure settings table exists
                    if not trackedBuffs[index].settings then
                        trackedBuffs[index].settings = {}
                    end
                    trackedBuffs[index].settings.generators = trackedBuffs[index].settings.generators or {}
                    trackedBuffs[index].settings.spenders = trackedBuffs[index].settings.spenders or {}
                    trackedBuffs[index].settings.maxStacks = trackedBuffs[index].settings.maxStacks or 10
                    trackedBuffs[index].settings.stackDuration = trackedBuffs[index].settings.stackDuration or 30
                elseif val == "spell" then
                    -- Initialize trigger for spell mode
                    if not trackedBuffs[index].trigger then
                        trackedBuffs[index].trigger = {}
                    end
                    trackedBuffs[index].trigger.type = "spell"
                    trackedBuffs[index].trigger.spellID = trackedBuffs[index].spellID or 0
                    trackedBuffs[index].trigger.hideWhenZero = false
                end
                DDingUI:UpdateBuffTrackerBar()
                RefreshOptions()
            end
        end,
    }


    -- Spell Cooldown Mode Header
    options["tracked" .. index .. "_spellHeader"] = {
        type = "description",
        name = "\n|cff00ccff━━━ " .. (L["Spell Cooldown Settings"] or "Spell Cooldown Settings") .. " ━━━|r",
        order = orderBase + 0.55,
        width = "full",
        fontSize = "medium",
        hidden = hiddenIfNotSpell,
    }

    -- Spell ID Input
    options["tracked" .. index .. "_spellID"] = {
        type = "input",
        name = "    " .. (L["Spell ID"] or "Spell ID"),
        desc = L["Enter the spell ID to track cooldown for"] or "Enter the spell ID to track cooldown for",
        order = orderBase + 0.56,
        width = 1.0,
        hidden = hiddenIfNotSpell,
        get = function()
            local buff = GetTrackedBuff(index)
            if buff and buff.trigger and buff.trigger.spellID then
                return tostring(buff.trigger.spellID)
            end
            return "0"
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] then
                local spellID = tonumber(val) or 0
                if not trackedBuffs[index].trigger then trackedBuffs[index].trigger = {} end
                trackedBuffs[index].trigger.spellID = spellID
                trackedBuffs[index].spellID = spellID
                -- Auto-set name and icon from spell info
                if spellID > 0 then
                    local name = C_Spell.GetSpellName(spellID)
                    if name then trackedBuffs[index].name = name end
                    local info = C_Spell.GetSpellInfo(spellID)
                    if info and info.iconID then trackedBuffs[index].icon = info.iconID end
                end
                DDingUI:UpdateBuffTrackerBar()
                -- RefreshOptions() 제거 — 입력 중 리프레시 방지
            end
        end,
    }

    -- [Phase 1] Fill Direction (spell mode only)
    options["tracked" .. index .. "_spellFillDirection"] = {
        type = "select",
        name = "    " .. (L["Fill Direction"] or "Fill Direction"),
        desc = L["Bar fill direction during cooldown"] or "Bar fill direction during cooldown",
        order = orderBase + 0.57,
        width = 0.7,
        hidden = hiddenIfNotSpell,
        values = {
            drain = L["Drain (shrink)"] or "Drain (shrink)",
            fill = L["Fill (grow)"] or "Fill (grow)",
        },
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.display and buff.display.spellBarFillDirection or "drain"
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] then
                if not trackedBuffs[index].display then trackedBuffs[index].display = {} end
                trackedBuffs[index].display.spellBarFillDirection = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- [Phase 2] Recharge Color (spell mode, charge spells)
    options["tracked" .. index .. "_spellRechargeColor"] = {
        type = "color",
        name = "    " .. (L["Recharge Color"] or "Recharge Color"),
        desc = L["Bar color while recharging"] or "Bar color while recharging",
        order = orderBase + 0.571,
        width = 0.5,
        hasAlpha = true,
        hidden = hiddenIfNotSpell,
        get = function()
            local buff = GetTrackedBuff(index)
            local c = buff and buff.display and buff.display.spellRechargeColor
            if c then return c[1], c[2], c[3], c[4] or 1 end
            local bc = buff and buff.display and buff.display.barColor or {1, 0.8, 0, 1}
            return bc[1], bc[2], bc[3], bc[4] or 1
        end,
        set = function(_, r, g, b, a)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] then
                if not trackedBuffs[index].display then trackedBuffs[index].display = {} end
                trackedBuffs[index].display.spellRechargeColor = {r, g, b, a or 1}
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- [Phase 2] Full Charge Color
    options["tracked" .. index .. "_spellFullChargeColor"] = {
        type = "color",
        name = "    " .. (L["Full Charge Color"] or "Full Charge Color"),
        desc = L["Bar color when all charges are full"] or "Bar color when all charges are full",
        order = orderBase + 0.572,
        width = 0.5,
        hasAlpha = true,
        hidden = hiddenIfNotSpell,
        get = function()
            local buff = GetTrackedBuff(index)
            local c = buff and buff.display and buff.display.spellFullChargeColor
            if c then return c[1], c[2], c[3], c[4] or 1 end
            local bc = buff and buff.display and buff.display.barColor or {1, 0.8, 0, 1}
            return bc[1], bc[2], bc[3], bc[4] or 1
        end,
        set = function(_, r, g, b, a)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] then
                if not trackedBuffs[index].display then trackedBuffs[index].display = {} end
                trackedBuffs[index].display.spellFullChargeColor = {r, g, b, a or 1}
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- [Phase 3] Ready Style
    options["tracked" .. index .. "_spellReadyStyle"] = {
        type = "select",
        name = "    " .. (L["Ready Style"] or "Ready Style"),
        desc = L["How the bar looks when spell is ready"] or "How the bar looks when spell is ready",
        order = orderBase + 0.573,
        width = 0.7,
        hidden = hiddenIfNotSpell,
        values = {
            full = L["Full Bar"] or "Full Bar",
            glow = L["Glow Effect"] or "Glow Effect",
            hide = L["Hide Bar"] or "Hide Bar",
        },
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.display and buff.display.spellReadyStyle or "full"
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] then
                if not trackedBuffs[index].display then trackedBuffs[index].display = {} end
                trackedBuffs[index].display.spellReadyStyle = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- [Phase 3] Ready Color
    options["tracked" .. index .. "_spellReadyColor"] = {
        type = "color",
        name = "    " .. (L["Ready Color"] or "Ready Color"),
        desc = L["Bar color when spell is ready"] or "Bar color when spell is ready",
        order = orderBase + 0.574,
        width = 0.5,
        hasAlpha = true,
        hidden = function()
            if hiddenIfNotSpell() then return true end
            local buff = GetTrackedBuff(index)
            return buff and buff.display and buff.display.spellReadyStyle == "hide"
        end,
        get = function()
            local buff = GetTrackedBuff(index)
            local c = buff and buff.display and buff.display.spellReadyColor
            if c then return c[1], c[2], c[3], c[4] or 1 end
            local bc = buff and buff.display and buff.display.barColor or {1, 0.8, 0, 1}
            return bc[1], bc[2], bc[3], bc[4] or 1
        end,
        set = function(_, r, g, b, a)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] then
                if not trackedBuffs[index].display then trackedBuffs[index].display = {} end
                trackedBuffs[index].display.spellReadyColor = {r, g, b, a or 1}
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- [Phase 3] Show "Ready" Text
    options["tracked" .. index .. "_spellShowReadyText"] = {
        type = "toggle",
        name = "    " .. (L["Show 'Ready' Text"] or "Show 'Ready' Text"),
        order = orderBase + 0.575,
        width = "full",
        hidden = hiddenIfNotSpell,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.display and buff.display.spellShowReadyText
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] then
                if not trackedBuffs[index].display then trackedBuffs[index].display = {} end
                trackedBuffs[index].display.spellShowReadyText = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Show Duration Inside Charge Slots (rune-timer style)
    options["tracked" .. index .. "_spellDurationInSlot"] = {
        type = "toggle",
        name = "    " .. (L["Show Duration In Slots"] or "칸 안에 표시"),
        desc = L["Show cooldown text inside each charge slot instead of the shared duration text"] or "각 충전 칸 안에 재사용 대기시간을 표시합니다",
        order = orderBase + 0.5755,
        width = "full",
        hidden = hiddenIfNotSpell,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.display and buff.display.spellDurationInSlot
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] then
                if not trackedBuffs[index].display then trackedBuffs[index].display = {} end
                trackedBuffs[index].display.spellDurationInSlot = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- [Phase 4] Color Curve Toggle
    options["tracked" .. index .. "_spellColorCurve"] = {
        type = "toggle",
        name = "    " .. (L["Color Curve (Time → Color)"] or "Color Curve (Time → Color)"),
        desc = L["Bar color changes based on remaining cooldown: Green → Yellow → Red"] or "Bar color changes based on remaining cooldown: Green → Yellow → Red",
        order = orderBase + 0.576,
        width = "full",
        hidden = hiddenIfNotSpell,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.display and buff.display.spellColorCurveEnabled
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] then
                if not trackedBuffs[index].display then trackedBuffs[index].display = {} end
                trackedBuffs[index].display.spellColorCurveEnabled = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Manual Mode Header
    options["tracked" .. index .. "_manualHeader"] = {
        type = "description",
        name = "\n|cffff8800━━━ " .. (L["Manual Tracking Settings"] or "Manual Tracking Settings") .. " ━━━|r",
        order = orderBase + 0.6,
        width = "full",
        fontSize = "medium",
        hidden = hiddenIfNotManual,
    }

    -- Generators Input (Trigger Spells)
    -- Format: spellID, spellID:stacks, spellID:stacks:duration
    -- Examples: 12345 (1 stack, refresh), 12345:2 (2 stacks, refresh), 12345:1:5 (1 stack, +5s), 12345:0:10 (+10s only)
    options["tracked" .. index .. "_generators"] = {
        type = "input",
        name = "    " .. (L["Trigger Spells (IDs)"] or "Trigger Spells (IDs)"),
        desc = L["Spell IDs with flexible format. Examples: 12345 (1 stack), 12345:2 (2 stacks), 12345:1:5 (1 stack +5s), 12345:0:10 (+10s only)"] or "Spell IDs with flexible format. Examples: 12345 (1 stack), 12345:2 (2 stacks), 12345:1:5 (1 stack +5s), 12345:0:10 (+10s only)",
        order = orderBase + 0.7,
        width = 1.5,
        hidden = hiddenIfNotManual,
        get = function()
            local buff = GetTrackedBuff(index)
            if not buff or not buff.settings or not buff.settings.generators then return "" end
            local parts = {}
            for _, gen in ipairs(buff.settings.generators) do
                if gen.spellID and gen.spellID > 0 then
                    local str = tostring(gen.spellID)
                    local hasStacks = gen.stacks and gen.stacks ~= 1
                    local hasDuration = gen.duration ~= nil

                    if hasDuration then
                        -- Full format: spellID:stacks:duration
                        str = str .. ":" .. (gen.stacks or 1) .. ":" .. gen.duration
                    elseif hasStacks then
                        -- Short format: spellID:stacks
                        str = str .. ":" .. gen.stacks
                    end
                    table.insert(parts, str)
                end
            end
            return table.concat(parts, ", ")
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if not trackedBuffs[index] then return end
            -- Ensure settings table exists
            if not trackedBuffs[index].settings then
                trackedBuffs[index].settings = {}
            end
            local generators = {}
            for part in string.gmatch(val, "[^,]+") do
                part = strtrim(part)
                -- Parse: spellID or spellID:stacks or spellID:stacks:duration
                local spellID, stacks, duration = strmatch(part, "(%d+):?(%d*):?(%d*)")
                spellID = tonumber(spellID)
                stacks = tonumber(stacks)  -- nil if empty
                duration = tonumber(duration)  -- nil if empty

                if spellID and spellID > 0 then
                    local gen = { spellID = spellID }
                    -- Default stacks to 1 if not specified
                    gen.stacks = stacks or 1
                    -- Only set duration if explicitly specified
                    if duration then
                        gen.duration = duration
                    end
                    table.insert(generators, gen)
                end
            end
            trackedBuffs[index].settings.generators = generators
            DDingUI:UpdateBuffTrackerBar()
        end,
    }

    -- Spenders Input (Consume Spells)
    options["tracked" .. index .. "_spenders"] = {
        type = "input",
        name = "    " .. (L["Spender Spells (IDs)"] or "Spender Spells (IDs)"),
        desc = L["Spell IDs that consume stacks (comma separated). Format: spellID or spellID:consume"] or "Spell IDs that consume stacks (comma separated). Format: spellID or spellID:consume",
        order = orderBase + 0.8,
        width = 1.5,
        hidden = hiddenIfNotManual,
        get = function()
            local buff = GetTrackedBuff(index)
            if not buff or not buff.settings or not buff.settings.spenders then return "" end
            local parts = {}
            for _, spend in ipairs(buff.settings.spenders) do
                if spend.spellID and spend.spellID > 0 then
                    if spend.consume and spend.consume ~= 1 then
                        table.insert(parts, spend.spellID .. ":" .. spend.consume)
                    else
                        table.insert(parts, tostring(spend.spellID))
                    end
                end
            end
            return table.concat(parts, ", ")
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if not trackedBuffs[index] then return end
            -- Ensure settings table exists
            if not trackedBuffs[index].settings then
                trackedBuffs[index].settings = {}
            end
            local spenders = {}
            for part in string.gmatch(val, "[^,]+") do
                part = strtrim(part)
                local spellID, consume = strmatch(part, "(%d+):?(%d*)")
                spellID = tonumber(spellID)
                consume = tonumber(consume) or 1
                if spellID and spellID > 0 then
                    table.insert(spenders, { spellID = spellID, consume = consume })
                end
            end
            trackedBuffs[index].settings.spenders = spenders
            DDingUI:UpdateBuffTrackerBar()
        end,
    }

    -- Manual Mode Help Text
    options["tracked" .. index .. "_manualHelp"] = {
        type = "description",
        name = "    |cff888888" .. (L["Comma separated. ID (1 stack), ID:2 (2 stacks), ID:1:5 (+5s), ID:0:10 (duration only)"] or "Comma separated. ID (1 stack), ID:2 (2 stacks), ID:1:5 (+5s), ID:0:10 (duration only)") .. "|r",
        order = orderBase + 0.85,
        width = 3.0,
        hidden = hiddenIfNotManual,
    }

    -- Manual Buff Name
    options["tracked" .. index .. "_manualName"] = {
        type = "input",
        name = "    " .. (L["Name"] or "Name"),
        desc = L["Display name for this manual buff"] or "Display name for this manual buff",
        order = orderBase + 0.86,
        width = 1.0,
        hidden = hiddenIfNotManual,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.name or ""
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] then
                trackedBuffs[index].name = val ~= "" and val or "Manual Buff"
                DDingUI:UpdateBuffTrackerBar()
                -- RefreshOptions() 제거 - 입력 중 리프레시 방지
            end
        end,
    }

    -- Manual Buff Icon ID
    options["tracked" .. index .. "_manualIcon"] = {
        type = "input",
        name = "    " .. (L["Icon ID"] or "Icon ID"),
        desc = L["Spell ID or texture ID for the icon (use Wowhead)"] or "Spell ID or texture ID for the icon (use Wowhead)",
        order = orderBase + 0.87,
        width = 0.7,
        hidden = hiddenIfNotManual,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.icon and tostring(buff.icon) or ""
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] then
                local iconID = tonumber(val)
                if iconID and iconID > 0 then
                    -- Try to get spell texture, otherwise use raw ID
                    local texture = C_Spell.GetSpellTexture(iconID) or iconID
                    trackedBuffs[index].icon = texture
                end
                DDingUI:UpdateBuffTrackerBar()
                -- RefreshOptions() 제거 - 입력 중 리프레시 방지
            end
        end,
    }

    -- ============================================================
    -- ICON MODE OPTIONS (order 1.1 ~ 1.9)
    -- ============================================================

    -- Icon header
    options["tracked" .. index .. "_iconHeader"] = {
        type = "description",
        name = "\n|cff8888ff━━━ " .. (L["Icon Settings"] or "Icon Settings") .. " ━━━|r",
        order = orderBase + 1.1,
        width = "full",
        fontSize = "medium",
        hidden = hiddenIfNotIcon,
    }

    -- Animation Type (expanded with glow types and hover/spin)
    options["tracked" .. index .. "_iconAnimation"] = {
        type = "select",
        name = "    " .. (L["Animation"] or "Animation"),
        order = orderBase + 1.2,
        width = 0.8,
        hidden = hiddenIfNotIcon,
        values = {
            none = L["None"] or "None",
            hover = L["Hover"] or "Hover",
            pulse = L["Pulse"] or "Pulse",
            flash = L["Flash"] or "Flash",
            spin = L["Spin"] or "Spin",
            pixel = L["Pixel Glow"] or "Pixel Glow",
            autocast = L["AutoCast Glow"] or "AutoCast Glow",
            button = L["Button Glow"] or "Button Glow",
            proc = L["Proc Glow"] or "Proc Glow",
        },
        sorting = { "none", "hover", "pulse", "flash", "spin", "pixel", "autocast", "button", "proc" },
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.iconAnimation or "button"
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.iconAnimation = val
                DDingUI:UpdateBuffTrackerBar()
                RefreshOptions()
            end
        end,
    }

    -- Helper: Check if glow options should be shown
    local function hiddenIfNotIconGlow()
        if hiddenIfNotIcon() then return true end
        local buff = GetTrackedBuff(index)
        local anim = buff and buff.settings and buff.settings.iconAnimation or "button"
        return anim ~= "pixel" and anim ~= "autocast" and anim ~= "button" and anim ~= "proc"
    end

    -- Glow When Inactive (reverse glow condition)
    options["tracked" .. index .. "_glowWhenInactive"] = {
        type = "toggle",
        name = "    " .. (L["Glow when inactive"] or "Glow when inactive"),
        desc = L["Apply glow effect when buff is NOT active (reverse condition)"] or "Apply glow effect when buff is NOT active (reverse condition)",
        order = orderBase + 1.205,
        width = 1.0,
        hidden = hiddenIfNotIconGlow,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.glowWhenInactive
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.glowWhenInactive = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Glow Color
    options["tracked" .. index .. "_glowColor"] = {
        type = "color",
        name = "        " .. (L["Glow Color"] or "Glow Color"),
        order = orderBase + 1.21,
        width = 0.5,
        hasAlpha = true,
        hidden = hiddenIfNotIconGlow,
        get = function()
            local buff = GetTrackedBuff(index)
            local c = buff and buff.settings and buff.settings.glowColor or { 1, 0.9, 0.5, 1 }
            return c[1], c[2], c[3], c[4] or 1
        end,
        set = function(_, r, g, b, a)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.glowColor = { r, g, b, a }
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Glow Lines/Particles
    options["tracked" .. index .. "_glowLines"] = {
        type = "range",
        name = "        " .. (L["Lines"] or "Lines"),
        desc = L["Number of glow lines/particles"] or "Number of glow lines/particles",
        order = orderBase + 1.22,
        width = 0.5,
        min = 1, max = 20, step = 1,
        hidden = hiddenIfNotIconGlow,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.glowLines or 8
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.glowLines = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Glow Frequency
    options["tracked" .. index .. "_glowFrequency"] = {
        type = "range",
        name = "        " .. (L["Speed"] or "Speed"),
        desc = L["Animation speed"] or "Animation speed",
        order = orderBase + 1.23,
        width = 0.5,
        min = 0.05, max = 1, step = 0.05,
        hidden = hiddenIfNotIconGlow,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.glowFrequency or 0.25
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.glowFrequency = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Glow Thickness/Scale
    options["tracked" .. index .. "_glowThickness"] = {
        type = "range",
        name = "        " .. (L["Thickness"] or "Thickness"),
        desc = L["Glow thickness/scale"] or "Glow thickness/scale",
        order = orderBase + 1.24,
        width = 0.5,
        min = 1, max = 10, step = 1,
        hidden = hiddenIfNotIconGlow,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.glowThickness or 2
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.glowThickness = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Glow X Offset
    options["tracked" .. index .. "_glowXOffset"] = {
        type = "range",
        name = "        " .. (L["Glow X"] or "Glow X"),
        order = orderBase + 1.25,
        width = 0.4,
        min = -20, max = 20, step = 0.1,
        hidden = hiddenIfNotIconGlow,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.glowXOffset or 0
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.glowXOffset = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Glow Y Offset
    options["tracked" .. index .. "_glowYOffset"] = {
        type = "range",
        name = "        " .. (L["Glow Y"] or "Glow Y"),
        order = orderBase + 1.26,
        width = 0.4,
        min = -20, max = 20, step = 0.1,
        hidden = hiddenIfNotIconGlow,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.glowYOffset or 0
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.glowYOffset = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Icon Source
    options["tracked" .. index .. "_iconSource"] = {
        type = "select",
        name = "    " .. (L["Icon Source"] or "Icon Source"),
        order = orderBase + 1.3,
        width = 0.7,
        hidden = hiddenIfNotIcon,
        values = {
            buff = L["Buff Icon"] or "Buff Icon",
            custom = L["Custom Icon"] or "Custom Icon",
        },
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.iconSource or "buff"
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.iconSource = val
                DDingUI:UpdateBuffTrackerBar()
                RefreshOptions()
            end
        end,
    }

    -- Custom Icon ID
    options["tracked" .. index .. "_customIconID"] = {
        type = "input",
        name = "    " .. (L["Custom Icon ID"] or "Custom Icon ID"),
        desc = L["Enter spell ID or texture ID"] or "Enter spell ID or texture ID",
        order = orderBase + 1.4,
        width = 0.7,
        hidden = function()
            if hiddenIfNotIcon() then return true end
            local buff = GetTrackedBuff(index)
            return not buff or not buff.settings or buff.settings.iconSource ~= "custom"
        end,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and tostring(buff.settings.customIconID or "")
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.customIconID = tonumber(val) or 0
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Icon Size
    options["tracked" .. index .. "_iconSize"] = {
        type = "range",
        name = "    " .. (L["Icon Size"] or "Icon Size"),
        order = orderBase + 1.5,
        width = 0.7,
        min = 16, max = 128, step = 1,
        hidden = hiddenIfNotIcon,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.iconSize or 32
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.iconSize = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Icon Attach To
    options["tracked" .. index .. "_iconAttachTo"] = {
        type = "select",
        name = "    " .. (L["Attach To"] or "Attach To"),
        desc = L["Attach To Desc"] or "Select the frame to attach this icon to",
        order = orderBase + 1.55,
        width = 1.0,
        hidden = hiddenIfNotIcon,
        values = function()
            -- [FIX] 하드코딩 → GetViewerOptions() 사용
            local frames = {
                ["UIParent"] = "UIParent",
                ["PlayerFrame"] = "PlayerFrame",
            }
            if DDingUI.GetViewerOptions then
                for k, v in pairs(DDingUI:GetViewerOptions()) do
                    frames[k] = v
                end
            end
            if _G["DDingUIResourceBarFrame"] then
                frames["DDingUIResourceBarFrame"] = "Resource Bar"
            end
            if _G["DDingUIComboPointsFrame"] then
                frames["DDingUIComboPointsFrame"] = "Combo Points"
            end
            if _G["DDingUIHealthBarFrame"] then
                frames["DDingUIHealthBarFrame"] = "Health Bar"
            end
            return frames
        end,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.iconAttachTo or defaultSpecConfig.attachTo
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.iconAttachTo = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Icon Anchor Point
    options["tracked" .. index .. "_iconAnchorPoint"] = {
        type = "select",
        name = "    " .. (L["Anchor Point"] or "Anchor Point"),
        desc = L["Anchor Point Desc"] or "Select the anchor point on the target frame",
        order = orderBase + 1.56,
        width = 0.7,
        hidden = hiddenIfNotIcon,
        values = {
            ["TOP"] = L["Top"] or "Top",
            ["BOTTOM"] = L["Bottom"] or "Bottom",
            ["LEFT"] = L["Left"] or "Left",
            ["RIGHT"] = L["Right"] or "Right",
            ["CENTER"] = L["Center"] or "Center",
            ["TOPLEFT"] = L["Top Left"] or "Top Left",
            ["TOPRIGHT"] = L["Top Right"] or "Top Right",
            ["BOTTOMLEFT"] = L["Bottom Left"] or "Bottom Left",
            ["BOTTOMRIGHT"] = L["Bottom Right"] or "Bottom Right",
        },
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.iconAnchorPoint or defaultSpecConfig.anchorPoint
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.iconAnchorPoint = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Icon Self Point / 기준점
    options["tracked" .. index .. "_iconSelfPoint"] = {
        type = "select",
        name = "    " .. (L["Self Point"] or "기준점"),
        desc = L["Which point of the icon itself is used for anchoring"] or "아이콘 자체의 어느 지점을 기준으로 앵커링할지 설정",
        order = orderBase + 1.57,
        width = 0.7,
        hidden = hiddenIfNotIcon,
        values = {
            ["TOP"] = L["Top"] or "Top",
            ["BOTTOM"] = L["Bottom"] or "Bottom",
            ["LEFT"] = L["Left"] or "Left",
            ["RIGHT"] = L["Right"] or "Right",
            ["CENTER"] = L["Center"] or "Center",
            ["TOPLEFT"] = L["Top Left"] or "Top Left",
            ["TOPRIGHT"] = L["Top Right"] or "Top Right",
            ["BOTTOMLEFT"] = L["Bottom Left"] or "Bottom Left",
            ["BOTTOMRIGHT"] = L["Bottom Right"] or "Bottom Right",
        },
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.iconSelfPoint or "CENTER"
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.iconSelfPoint = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Icon Offset X
    options["tracked" .. index .. "_iconOffsetX"] = {
        type = "range",
        name = "    " .. (L["Icon X Offset"] or "Icon X Offset"),
        order = orderBase + 1.6,
        width = 0.7,
        min = -500, max = 500, step = 0.1,
        hidden = hiddenIfNotIcon,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.iconOffsetX or 0
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.iconOffsetX = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Icon Offset Y
    options["tracked" .. index .. "_iconOffsetY"] = {
        type = "range",
        name = "    " .. (L["Icon Y Offset"] or "Icon Y Offset"),
        order = orderBase + 1.7,
        width = 0.7,
        min = -500, max = 500, step = 0.1,
        hidden = hiddenIfNotIcon,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.iconOffsetY or 0
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.iconOffsetY = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Show Icon Border
    options["tracked" .. index .. "_showIconBorder"] = {
        type = "toggle",
        name = "    " .. (L["Show Icon Border"] or "Show Icon Border"),
        order = orderBase + 1.8,
        width = 0.7,
        hidden = hiddenIfNotIcon,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.showIconBorder ~= false
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.showIconBorder = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Icon Border Size
    options["tracked" .. index .. "_iconBorderSize"] = {
        type = "range",
        name = "    " .. (L["Border Size"] or "Border Size"),
        order = orderBase + 1.801,
        width = 0.7,
        min = 0, max = 5, step = 1,
        hidden = function()
            if hiddenIfNotIcon() then return true end
            local buff = GetTrackedBuff(index)
            return not (buff and buff.settings and buff.settings.showIconBorder ~= false)
        end,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.iconBorderSize or 1
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.iconBorderSize = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Icon Border Color
    options["tracked" .. index .. "_iconBorderColor"] = {
        type = "color",
        name = "    " .. (L["Border Color"] or "Border Color"),
        order = orderBase + 1.802,
        width = 0.7,
        hasAlpha = true,
        hidden = function()
            if hiddenIfNotIcon() then return true end
            local buff = GetTrackedBuff(index)
            return not (buff and buff.settings and buff.settings.showIconBorder ~= false)
        end,
        get = function()
            local buff = GetTrackedBuff(index)
            local c = buff and buff.settings and buff.settings.iconBorderColor or { 0, 0, 0, 1 }
            return c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1
        end,
        set = function(_, r, g, b, a)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.iconBorderColor = { r, g, b, a }
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Icon Zoom (texture crop)
    options["tracked" .. index .. "_iconZoom"] = {
        type = "range",
        name = "    " .. (L["Icon Zoom"] or "Icon Zoom"),
        desc = L["Crops the edges of icons (higher = more zoom)"] or "Crops the edges of icons (higher = more zoom)",
        order = orderBase + 1.803,
        width = 0.7,
        min = 0, max = 0.2, step = 0.01,
        hidden = hiddenIfNotIcon,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.iconZoom or 0.08
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.iconZoom = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Icon Aspect Ratio
    options["tracked" .. index .. "_iconAspectRatio"] = {
        type = "range",
        name = "    " .. (L["Aspect Ratio"] or "Aspect Ratio"),
        desc = L["Control the icon aspect ratio. 1.0 = square, >1.0 = wider, <1.0 = taller"] or "Control the icon aspect ratio. 1.0 = square, >1.0 = wider, <1.0 = taller",
        order = orderBase + 1.804,
        width = 0.7,
        min = 0.5, max = 2.0, step = 0.05,
        hidden = hiddenIfNotIcon,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.iconAspectRatio or 1.0
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.iconAspectRatio = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Icon Always Show In Combat (아이콘 전투중 항상 표시)
    options["tracked" .. index .. "_iconShowInCombat"] = {
        type = "toggle",
        name = "    " .. (L["Always show in combat"] or "Always show in combat"),
        desc = L["Show during combat even when stacks are 0"] or "Show during combat even when stacks are 0",
        order = orderBase + 1.8041,
        width = 1.0,
        hidden = hiddenIfNotIcon,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.showInCombat
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.showInCombat = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Icon Only In Combat (아이콘 전투 중에만 표시)
    options["tracked" .. index .. "_iconOnlyInCombat"] = {
        type = "toggle",
        name = "    " .. (L["Only show in combat"] or "Only show in combat"),
        desc = L["Hide when out of combat"] or "Hide when out of combat",
        order = orderBase + 1.80415,
        width = 1.0,
        hidden = hiddenIfNotIcon,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.onlyInCombat
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.onlyInCombat = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Icon Show Only When Inactive (비활성화 시에만 표시)
    options["tracked" .. index .. "_showOnlyWhenInactive"] = {
        type = "toggle",
        name = "    " .. (L["Show only when inactive"] or "Show only when inactive"),
        desc = L["Only show icon when buff is NOT active"] or "Only show icon when buff is NOT active",
        order = orderBase + 1.8042,
        width = 1.0,
        hidden = hiddenIfNotIcon,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.showOnlyWhenInactive
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.showOnlyWhenInactive = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Icon Desaturate (when not active)
    options["tracked" .. index .. "_iconDesaturate"] = {
        type = "toggle",
        name = "    " .. (L["Desaturate When Inactive"] or "Desaturate When Inactive"),
        desc = L["Desaturate the icon when the buff is not active"] or "Desaturate the icon when the buff is not active",
        order = orderBase + 1.805,
        width = 1.0,
        hidden = hiddenIfNotIcon,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.iconDesaturate or false
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.iconDesaturate = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Icon Stack Text Header
    options["tracked" .. index .. "_iconStackHeader"] = {
        type = "description",
        name = "\n|cffffaa00━━━ " .. (L["Stack Text (Icon)"] or "Stack Text (Icon)") .. " ━━━|r",
        order = orderBase + 1.806,
        width = "full",
        fontSize = "medium",
        hidden = hiddenIfNotIcon,
    }

    -- Show Stack Text
    options["tracked" .. index .. "_iconShowStackText"] = {
        type = "toggle",
        name = "    " .. (L["Show Stack Text"] or "Show Stack Text"),
        order = orderBase + 1.8061,
        width = 0.7,
        hidden = hiddenIfNotIcon,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.iconShowStackText ~= false
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.iconShowStackText = val
                DDingUI:UpdateBuffTrackerBar()
                RefreshOptions()  -- 하위 옵션 hidden 상태 즉시 업데이트
            end
        end,
    }

    -- Helper for hiding stack text options when stack text is disabled
    local function hiddenIfStackTextDisabled()
        if hiddenIfNotIcon() then return true end
        local buff = GetTrackedBuff(index)
        return not (buff and buff.settings and buff.settings.iconShowStackText ~= false)
    end

    -- Stack Text Font
    options["tracked" .. index .. "_iconStackTextFont"] = {
        type = "select",
        name = "    " .. (L["Font"] or "Font"),
        order = orderBase + 1.8062,
        width = 1.0,
        hidden = hiddenIfStackTextDisabled,
        dialogControl = "LSM30_Font",
        values = function() return DDingUI:GetFontValues() end,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.iconStackTextFont or DDingUI.DEFAULT_FONT_NAME
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.iconStackTextFont = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Stack Text Size
    options["tracked" .. index .. "_iconStackTextSize"] = {
        type = "range",
        name = "    " .. (L["Size"] or "Size"),
        order = orderBase + 1.8063,
        width = 0.6,
        min = 6, max = 24, step = 1,
        hidden = hiddenIfStackTextDisabled,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.iconStackTextSize or 12
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.iconStackTextSize = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Stack Text Color
    options["tracked" .. index .. "_iconStackTextColor"] = {
        type = "color",
        name = "    " .. (L["Color"] or "Color"),
        order = orderBase + 1.8064,
        width = 0.5,
        hasAlpha = true,
        hidden = hiddenIfStackTextDisabled,
        get = function()
            local buff = GetTrackedBuff(index)
            local c = buff and buff.settings and buff.settings.iconStackTextColor or { 1, 1, 1, 1 }
            return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
        end,
        set = function(_, r, g, b, a)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.iconStackTextColor = { r, g, b, a }
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Stack Text Anchor
    options["tracked" .. index .. "_iconStackTextAnchor"] = {
        type = "select",
        name = "    " .. (L["Position"] or "Position"),
        order = orderBase + 1.8065,
        width = 0.7,
        hidden = hiddenIfStackTextDisabled,
        values = {
            TOPLEFT = L["Top Left"] or "Top Left",
            TOP = L["Top"] or "Top",
            TOPRIGHT = L["Top Right"] or "Top Right",
            LEFT = L["Left"] or "Left",
            CENTER = L["Center"] or "Center",
            RIGHT = L["Right"] or "Right",
            BOTTOMLEFT = L["Bottom Left"] or "Bottom Left",
            BOTTOM = L["Bottom"] or "Bottom",
            BOTTOMRIGHT = L["Bottom Right"] or "Bottom Right",
        },
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.iconStackTextAnchor or "BOTTOMRIGHT"
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.iconStackTextAnchor = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Stack Text Offset X
    options["tracked" .. index .. "_iconStackTextOffsetX"] = {
        type = "range",
        name = "    " .. (L["X Offset"] or "X Offset"),
        order = orderBase + 1.8066,
        width = 0.5,
        min = -20, max = 20, step = 0.1,
        hidden = hiddenIfStackTextDisabled,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.iconStackTextOffsetX or -2
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.iconStackTextOffsetX = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Stack Text Offset Y
    options["tracked" .. index .. "_iconStackTextOffsetY"] = {
        type = "range",
        name = "    " .. (L["Y Offset"] or "Y Offset"),
        order = orderBase + 1.8067,
        width = 0.5,
        min = -20, max = 20, step = 0.1,
        hidden = hiddenIfStackTextDisabled,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.iconStackTextOffsetY or 2
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.iconStackTextOffsetY = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Stack Text Outline
    options["tracked" .. index .. "_iconStackTextOutline"] = {
        type = "select",
        name = "    " .. (L["Outline"] or "Outline"),
        order = orderBase + 1.8068,
        width = 0.6,
        hidden = hiddenIfStackTextDisabled,
        values = {
            [""] = L["None"] or "None",
            OUTLINE = L["Outline"] or "Outline",
            THICKOUTLINE = L["Thick Outline"] or "Thick Outline",
        },
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.iconStackTextOutline or "OUTLINE"
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.iconStackTextOutline = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- ============================================================
    -- SOUND MODE OPTIONS (order 1.81 ~ 1.99)
    -- ============================================================

    -- Sound header
    options["tracked" .. index .. "_soundHeader"] = {
        type = "description",
        name = "\n|cffff8888━━━ " .. (L["Sound Settings"] or "Sound Settings") .. " ━━━|r",
        order = orderBase + 1.81,
        width = "full",
        fontSize = "medium",
        hidden = hiddenIfNotSound,
    }

    -- Sound File (SharedMedia) - LSM:List returns sorted list
    options["tracked" .. index .. "_soundFile"] = {
        type = "select",
        name = "    " .. (L["Sound"] or "Sound"),
        desc = L["Select a sound to play"] or "Select a sound to play",
        order = orderBase + 1.82,
        width = 1.2,
        hidden = hiddenIfNotSound,
        values = function()
            local values = {}
            local list = LSM:List("sound")
            for _, name in ipairs(list) do
                values[name] = name
            end
            return values
        end,
        sorting = function()
            return LSM:List("sound")
        end,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.soundFile or "None"
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.soundFile = val
                -- 선택 시 미리듣기
                if val and val ~= "None" then
                    local soundPath = LSM:Fetch("sound", val)
                    if soundPath then
                        PlaySoundFile(soundPath, "Master")
                    end
                end
            end
        end,
    }

    -- [12.0.1] Custom Sound Path
    options["tracked" .. index .. "_soundCustomPath"] = {
        type = "input",
        name = "    " .. (L["Custom Sound Path"] or "Custom Sound Path"),
        desc = (L["Enter a custom sound file path (mp3/ogg/wav). Overrides the dropdown above when set."] or "Enter a custom sound file path (mp3/ogg/wav). Overrides the dropdown above when set.") .. "\n\n" .. (L["Example"] or "Example") .. ": Interface\\AddOns\\MyAddon\\sounds\\alert.ogg",
        order = orderBase + 1.822,
        width = 1.6,
        hidden = hiddenIfNotSound,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.soundCustomPath or ""
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                -- Validate extension
                if val and val ~= "" then
                    local ext = val:lower():match("%.(%w+)$")
                    if ext ~= "mp3" and ext ~= "ogg" and ext ~= "wav" then
                        print(CDM_PREFIX .. "|cffff4444" .. (L["Invalid sound format. Use mp3, ogg, or wav."] or "Invalid sound format. Use mp3, ogg, or wav."))
                        return
                    end
                end
                trackedBuffs[index].settings.soundCustomPath = val or ""
                -- Preview if path set
                if val and val ~= "" then
                    local channel = trackedBuffs[index].settings.soundChannel or "Master"
                    PlaySoundFile(val, channel)
                end
            end
        end,
    }

    -- Test Sound Button
    options["tracked" .. index .. "_testSound"] = {
        type = "execute",
        name = L["Test"] or "Test",
        order = orderBase + 1.823,
        width = 0.4,
        hidden = hiddenIfNotSound,
        func = function()
            local buff = GetTrackedBuff(index)
            if not buff or not buff.settings then return end
            local channel = buff.settings.soundChannel or "Master"
            -- Custom path takes priority
            local customPath = buff.settings.soundCustomPath or ""
            if customPath ~= "" then
                local ext = customPath:lower():match("%.(%w+)$")
                if ext == "mp3" or ext == "ogg" or ext == "wav" then
                    PlaySoundFile(customPath, channel)
                else
                    print(CDM_PREFIX .. "|cffff4444" .. (L["Invalid sound format. Use mp3, ogg, or wav."] or "Invalid sound format. Use mp3, ogg, or wav."))
                end
                return
            end
            -- Fallback to LSM
            if buff.settings.soundFile and buff.settings.soundFile ~= "None" then
                local soundPath = LSM:Fetch("sound", buff.settings.soundFile)
                if soundPath then
                    PlaySoundFile(soundPath, channel)
                end
            end
        end,
    }

    -- Sound Channel
    options["tracked" .. index .. "_soundChannel"] = {
        type = "select",
        name = "    " .. (L["Channel"] or "Channel"),
        order = orderBase + 1.84,
        width = 0.6,
        hidden = hiddenIfNotSound,
        values = {
            Master = L["Master"] or "Master",
            SFX = L["SFX"] or "SFX",
            Music = L["Music"] or "Music",
            Ambience = L["Ambience"] or "Ambience",
            Dialog = L["Dialog"] or "Dialog",
        },
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.soundChannel or "Master"
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.soundChannel = val
            end
        end,
    }

    -- Sound Trigger
    options["tracked" .. index .. "_soundTrigger"] = {
        type = "select",
        name = "    " .. (L["Play When"] or "Play When"),
        desc = L["When should the sound play?"] or "When should the sound play?",
        order = orderBase + 1.85,
        width = 1.0,
        hidden = hiddenIfNotSound,
        values = {
            start = L["Buff Starts"] or "Buff Starts",
            startDelay = L["After Buff Starts"] or "After Buff Starts",
            ["end"] = L["Buff Ends"] or "Buff Ends",
            endBefore = L["Before Buff Ends"] or "Before Buff Ends",
            interval = L["While Active (Interval)"] or "While Active (Interval)",
        },
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.soundTrigger or "start"
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.soundTrigger = val
                RefreshOptions()
            end
        end,
    }

    -- Sound Start Delay (seconds after buff starts)
    options["tracked" .. index .. "_soundStartDelay"] = {
        type = "range",
        name = "    " .. (L["Seconds After Start"] or "Seconds After Start"),
        order = orderBase + 1.86,
        width = 0.9,
        min = 0, max = 60, step = 0.5,
        hidden = function()
            if hiddenIfNotSound() then return true end
            local buff = GetTrackedBuff(index)
            return not buff or not buff.settings or buff.settings.soundTrigger ~= "startDelay"
        end,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.soundStartDelay or 0
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.soundStartDelay = val
            end
        end,
    }

    -- Sound End Before (seconds before buff ends)
    options["tracked" .. index .. "_soundEndBefore"] = {
        type = "range",
        name = "    " .. (L["Seconds Before End"] or "Seconds Before End"),
        order = orderBase + 1.87,
        width = 0.9,
        min = 0, max = 60, step = 0.5,
        hidden = function()
            if hiddenIfNotSound() then return true end
            local buff = GetTrackedBuff(index)
            return not buff or not buff.settings or buff.settings.soundTrigger ~= "endBefore"
        end,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.soundEndBefore or 3
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.soundEndBefore = val
            end
        end,
    }

    -- Sound Interval (every X seconds while active)
    options["tracked" .. index .. "_soundInterval"] = {
        type = "range",
        name = "    " .. (L["Play Every (seconds)"] or "Play Every (seconds)"),
        order = orderBase + 1.88,
        width = 0.9,
        min = 0.5, max = 60, step = 0.5,
        hidden = function()
            if hiddenIfNotSound() then return true end
            local buff = GetTrackedBuff(index)
            return not buff or not buff.settings or buff.settings.soundTrigger ~= "interval"
        end,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.soundInterval or 5
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.soundInterval = val
            end
        end,
    }

    -- NOTE: Minimum Stacks removed - cannot compare secret values in WoW 12.0+

    -- ============================================================
    -- TEXT MODE OPTIONS (order 1.90 ~ 1.99)
    -- ============================================================

    -- Text header
    options["tracked" .. index .. "_textHeader"] = {
        type = "description",
        name = "\n|cffff88ff━━━ " .. (L["Text Settings"] or "Text Settings") .. " ━━━|r",
        order = orderBase + 1.90,
        width = "full",
        fontSize = "medium",
        hidden = hiddenIfNotText,
    }

    -- Text Display Mode
    options["tracked" .. index .. "_textDisplayMode"] = {
        type = "select",
        name = "    " .. (L["Display"] or "Display"),
        order = orderBase + 1.91,
        width = 0.7,
        hidden = hiddenIfNotText,
        values = {
            stacks = L["Stacks Count"] or "Stacks Count",
            duration = L["Duration"] or "Duration",
            name = L["Buff Name"] or "Buff Name",
            custom = L["Custom Text"] or "Custom Text",
        },
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.textDisplayMode or "stacks"
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.textDisplayMode = val
                DDingUI:UpdateBuffTrackerBar()
                RefreshOptions()
            end
        end,
    }

    -- Custom Text
    options["tracked" .. index .. "_customText"] = {
        type = "input",
        name = "    " .. (L["Custom Text"] or "Custom Text"),
        desc = L["Use %s for stacks, %d for duration"] or "Use %s for stacks, %d for duration",
        order = orderBase + 1.911,
        width = 1.0,
        hidden = function()
            if hiddenIfNotText() then return true end
            local buff = GetTrackedBuff(index)
            return not buff or not buff.settings or buff.settings.textDisplayMode ~= "custom"
        end,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.customText or ""
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.customText = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Text Attach To
    options["tracked" .. index .. "_textAnchorTo"] = {
        type = "select",
        name = "    " .. (L["Attach To"] or "Attach To"),
        order = orderBase + 1.92,
        width = 1.0,
        hidden = hiddenIfNotText,
        values = function()
            -- [FIX] GetViewerOptions 활용 + UIParent/PlayerFrame 추가
            local frames = {
                ["UIParent"] = "UIParent",
                ["PlayerFrame"] = "PlayerFrame",
            }
            local viewerOpts = GetViewerOptions()
            for k, v in pairs(viewerOpts) do
                frames[k] = v
            end
            if _G["DDingUIResourceBarFrame"] then
                frames["DDingUIResourceBarFrame"] = "Resource Bar"
            end
            return frames
        end,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.textAnchorTo or "DDingUI_Anchor_Cooldowns"
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.textAnchorTo = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Text Anchor Point
    options["tracked" .. index .. "_textAnchorPoint"] = {
        type = "select",
        name = "    " .. (L["Anchor Point"] or "Anchor Point"),
        order = orderBase + 1.93,
        width = 0.7,
        hidden = hiddenIfNotText,
        values = {
            ["TOPLEFT"] = L["Top Left"] or "Top Left",
            ["TOP"] = L["Top"] or "Top",
            ["TOPRIGHT"] = L["Top Right"] or "Top Right",
            ["LEFT"] = L["Left"] or "Left",
            ["CENTER"] = L["Center"] or "Center",
            ["RIGHT"] = L["Right"] or "Right",
            ["BOTTOMLEFT"] = L["Bottom Left"] or "Bottom Left",
            ["BOTTOM"] = L["Bottom"] or "Bottom",
            ["BOTTOMRIGHT"] = L["Bottom Right"] or "Bottom Right",
        },
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.textAnchorPoint or "CENTER"
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.textAnchorPoint = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Text Offset X
    options["tracked" .. index .. "_textModeOffsetX"] = {
        type = "range",
        name = "    " .. (L["X Offset"] or "X Offset"),
        order = orderBase + 1.94,
        width = 0.6,
        min = -500, max = 500, step = 0.1,
        hidden = hiddenIfNotText,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.textModeOffsetX or 0
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.textModeOffsetX = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Text Offset Y
    options["tracked" .. index .. "_textModeOffsetY"] = {
        type = "range",
        name = "    " .. (L["Y Offset"] or "Y Offset"),
        order = orderBase + 1.95,
        width = 0.6,
        min = -500, max = 500, step = 0.1,
        hidden = hiddenIfNotText,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.textModeOffsetY or 50
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.textModeOffsetY = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Text Size
    options["tracked" .. index .. "_textModeSize"] = {
        type = "range",
        name = "    " .. (L["Font Size"] or "Font Size"),
        order = orderBase + 1.96,
        width = 0.6,
        min = 8, max = 72, step = 1,
        hidden = hiddenIfNotText,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.textModeSize or 24
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.textModeSize = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Text Font
    options["tracked" .. index .. "_textModeFont"] = {
        type = "select",
        name = "    " .. (L["Font"] or "Font"),
        order = orderBase + 1.961,
        width = 1.0,
        hidden = hiddenIfNotText,
        dialogControl = "LSM30_Font",
        values = function() return DDingUI:GetFontValues() end,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.textModeFont or DDingUI.db.profile.defaultFont or DDingUI.DEFAULT_FONT_NAME
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.textModeFont = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Text Color
    options["tracked" .. index .. "_textModeColor"] = {
        type = "color",
        name = "    " .. (L["Text Color"] or "Text Color"),
        order = orderBase + 1.97,
        width = 0.6,
        hasAlpha = true,
        hidden = hiddenIfNotText,
        get = function()
            local buff = GetTrackedBuff(index)
            local c = buff and buff.settings and buff.settings.textModeColor or { 1, 1, 1, 1 }
            return c[1], c[2], c[3], c[4] or 1
        end,
        set = function(_, r, g, b, a)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.textModeColor = { r, g, b, a }
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Text Outline
    options["tracked" .. index .. "_textModeOutline"] = {
        type = "select",
        name = "    " .. (L["Outline"] or "Outline"),
        order = orderBase + 1.971,
        width = 0.6,
        hidden = hiddenIfNotText,
        values = {
            [""] = L["None"] or "None",
            ["OUTLINE"] = L["Outline"] or "Outline",
            ["THICKOUTLINE"] = L["Thick Outline"] or "Thick Outline",
            ["MONOCHROME"] = L["Monochrome"] or "Monochrome",
        },
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.textModeOutline or "OUTLINE"
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.textModeOutline = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Text Animation (expanded with glow types and hover/spin)
    options["tracked" .. index .. "_textAnimation"] = {
        type = "select",
        name = "    " .. (L["Animation"] or "Animation"),
        desc = L["Animation effect when buff is active"] or "Animation effect when buff is active",
        order = orderBase + 1.975,
        width = 0.8,
        hidden = hiddenIfNotText,
        values = {
            none = L["None"] or "None",
            hover = L["Hover"] or "Hover",
            pulse = L["Pulse"] or "Pulse",
            flash = L["Flash"] or "Flash",
            spin = L["Spin"] or "Spin",
            pixel = L["Pixel Glow"] or "Pixel Glow",
            autocast = L["AutoCast Glow"] or "AutoCast Glow",
            button = L["Button Glow"] or "Button Glow",
            proc = L["Proc Glow"] or "Proc Glow",
        },
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.textAnimation or "none"
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.textAnimation = val
                DDingUI:UpdateBuffTrackerBar()
                RefreshOptions()
            end
        end,
    }

    -- Helper: Check if text glow options should be shown
    local function hiddenIfNotTextGlow()
        if hiddenIfNotText() then return true end
        local buff = GetTrackedBuff(index)
        local anim = buff and buff.settings and buff.settings.textAnimation or "none"
        return anim ~= "pixel" and anim ~= "autocast" and anim ~= "button" and anim ~= "proc"
    end

    -- Text Glow Color
    options["tracked" .. index .. "_textGlowColor"] = {
        type = "color",
        name = "        " .. (L["Glow Color"] or "Glow Color"),
        order = orderBase + 1.9751,
        width = 0.5,
        hasAlpha = true,
        hidden = hiddenIfNotTextGlow,
        get = function()
            local buff = GetTrackedBuff(index)
            local c = buff and buff.settings and buff.settings.textGlowColor or { 1, 1, 0.3, 1 }
            return c[1], c[2], c[3], c[4] or 1
        end,
        set = function(_, r, g, b, a)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.textGlowColor = { r, g, b, a }
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Text Glow Lines/Particles
    options["tracked" .. index .. "_textGlowLines"] = {
        type = "range",
        name = "        " .. (L["Lines"] or "Lines"),
        desc = L["Number of glow lines/particles"] or "Number of glow lines/particles",
        order = orderBase + 1.9752,
        width = 0.5,
        min = 1, max = 20, step = 1,
        hidden = hiddenIfNotTextGlow,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.textGlowLines or 8
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.textGlowLines = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Text Glow Frequency
    options["tracked" .. index .. "_textGlowFrequency"] = {
        type = "range",
        name = "        " .. (L["Speed"] or "Speed"),
        desc = L["Animation speed"] or "Animation speed",
        order = orderBase + 1.9753,
        width = 0.5,
        min = 0.05, max = 1, step = 0.05,
        hidden = hiddenIfNotTextGlow,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.textGlowFrequency or 0.25
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.textGlowFrequency = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Text Glow Thickness/Scale
    options["tracked" .. index .. "_textGlowThickness"] = {
        type = "range",
        name = "        " .. (L["Thickness"] or "Thickness"),
        desc = L["Glow thickness/scale"] or "Glow thickness/scale",
        order = orderBase + 1.9754,
        width = 0.5,
        min = 1, max = 10, step = 1,
        hidden = hiddenIfNotTextGlow,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.textGlowThickness or 2
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.textGlowThickness = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Text Glow X Offset
    options["tracked" .. index .. "_textGlowXOffset"] = {
        type = "range",
        name = "        " .. (L["Glow X"] or "Glow X"),
        order = orderBase + 1.9755,
        width = 0.4,
        min = -20, max = 20, step = 0.1,
        hidden = hiddenIfNotTextGlow,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.textGlowXOffset or 0
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.textGlowXOffset = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Text Glow Y Offset
    options["tracked" .. index .. "_textGlowYOffset"] = {
        type = "range",
        name = "        " .. (L["Glow Y"] or "Glow Y"),
        order = orderBase + 1.9756,
        width = 0.4,
        min = -20, max = 20, step = 0.1,
        hidden = hiddenIfNotTextGlow,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.textGlowYOffset or 0
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.textGlowYOffset = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Show Icon with Text
    options["tracked" .. index .. "_textShowIcon"] = {
        type = "toggle",
        name = "    " .. (L["Show Icon"] or "Show Icon"),
        order = orderBase + 1.98,
        width = 0.5,
        hidden = hiddenIfNotText,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.textShowIcon ~= false
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.textShowIcon = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Text Icon Size
    options["tracked" .. index .. "_textIconSize"] = {
        type = "range",
        name = "    " .. (L["Icon Size"] or "Icon Size"),
        order = orderBase + 1.99,
        width = 0.6,
        min = 12, max = 64, step = 1,
        hidden = function()
            if hiddenIfNotText() then return true end
            local buff = GetTrackedBuff(index)
            return not buff or not buff.settings or not buff.settings.textShowIcon
        end,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.textIconSize or 24
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.textIconSize = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- ============================================================
    -- BAR MODE OPTIONS (only visible when displayType == "bar")
    -- ============================================================

    -- Bar header
    options["tracked" .. index .. "_barHeader"] = {
        type = "description",
        name = "\n|cff88ff88━━━ " .. (L["Bar Settings"] or "Bar Settings") .. " ━━━|r",
        order = orderBase + 1.991,
        width = "full",
        fontSize = "medium",
        hidden = hiddenIfNotBar,
    }

    -- Max Stacks (bar와 ring 둘 다 표시)
    options["tracked" .. index .. "_maxStacks"] = {
        type = "input",
        name = "    " .. (L["Max Stacks"] or "Max Stacks"),
        order = orderBase + 2,
        width = 0.5,
        hidden = function()
            if hiddenIfCollapsed() then return true end
            local buff = GetTrackedBuff(index)
            if not buff or (buff.displayType ~= "bar" and buff.displayType ~= "ring") then return true end
            -- Spell 모드: maxCharges 자동 감지, 수동 설정 불필요
            if buff.trigger and buff.trigger.type == "spell" then return true end
            return false
        end,
        get = function()
            local buff = GetTrackedBuff(index)
            return tostring(buff and buff.settings and buff.settings.maxStacks or 10)
        end,
        set = function(_, val)
            local num = tonumber(val)
            if not num or num < 1 then num = 1 end
            if num > 9999 then num = 9999 end
            num = math.floor(num)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.maxStacks = num
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Stack Duration (모든 displayType에서 표시, auto-detect 비활성화 시에만)
    options["tracked" .. index .. "_duration"] = {
        type = "range",
        name = "    " .. (L["Max Duration (sec)"] or "Max Duration (sec)"),
        desc = L["Maximum duration for manual countdown. Used by duration triggers and ring/bar fill."] or "Maximum duration for manual countdown. Used by duration triggers and ring/bar fill.",
        order = orderBase + 0.85,
        width = 0.55,
        min = 0, max = 600, step = 1,
        hidden = function()
            if hiddenIfCollapsed() then return true end
            local buff = GetTrackedBuff(index)
            if not buff then return true end
            if buff.trigger and buff.trigger.type == "spell" then return true end
            return buff.settings and buff.settings.dynamicDuration
        end,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.stackDuration or 30
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.stackDuration = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Dynamic Duration Toggle (bar와 ring 둘 다 표시)
    options["tracked" .. index .. "_dynamicDuration"] = {
        type = "toggle",
        name = "    " .. (L["Auto-detect duration"] or "지속시간 자동 감지"),
        desc = L["Automatically read duration from CDM when buff activates"] or "버프 활성화 시 CDM에서 지속시간 자동 읽기",
        order = orderBase + 3.5,
        width = "full",
        hidden = function()
            if hiddenIfCollapsed() then return true end
            local buff = GetTrackedBuff(index)
            if not buff or (buff.displayType ~= "bar" and buff.displayType ~= "ring") then return true end
            -- Spell 모드: CDM 지속시간 감지 불필요 (쿨다운 자체가 지속시간)
            if buff.trigger and buff.trigger.type == "spell" then return true end
            return false
        end,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.dynamicDuration
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.dynamicDuration = val
                -- 자동 모드 켤 때 기존 감지된 값 리셋
                if val then
                    trackedBuffs[index].settings._detectedDuration = nil
                end
                DDingUI:UpdateBuffTrackerBar()
                RefreshOptions()  -- UI 갱신
            end
        end,
    }

    -- Hide When Zero / Hide When Full Charge (spell 모드에서 레이블 변경)
    options["tracked" .. index .. "_hideWhenZero"] = {
        type = "toggle",
        name = function()
            local buff = GetTrackedBuff(index)
            local isSpell = buff and (buff.trackingMode == "spell" or (buff.trigger and buff.trigger.type == "spell"))
            if isSpell then
                return "    " .. (L["Hide when fully charged"] or "Hide when fully charged")
            end
            return "    " .. (L["Hide at 0 stacks"] or "Hide at 0 stacks")
        end,
        order = orderBase + 4,
        width = 0.7,
        hidden = function()
            if hiddenIfCollapsed() then return true end
            local buff = GetTrackedBuff(index)
            return not buff or (buff.displayType ~= "bar" and buff.displayType ~= "ring" and buff.displayType ~= "icon")
        end,
        get = function()
            local buff = GetTrackedBuff(index)
            if not buff or not buff.settings then return false end
            local isSpell = buff.trackingMode == "spell" or (buff.trigger and buff.trigger.type == "spell")
            if isSpell then
                return buff.settings.hideWhenFullCharge
            end
            return buff.settings.hideWhenZero
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                local buff = trackedBuffs[index]
                local isSpell = buff.trackingMode == "spell" or (buff.trigger and buff.trigger.type == "spell")
                if isSpell then
                    trackedBuffs[index].settings.hideWhenFullCharge = val
                else
                    trackedBuffs[index].settings.hideWhenZero = val
                end
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Show In Combat (bar와 ring 둘 다 표시)
    options["tracked" .. index .. "_showInCombat"] = {
        type = "toggle",
        name = "    " .. (L["Always show in combat"] or "Always show in combat"),
        desc = L["Show during combat even when stacks are 0"] or "Show during combat even when stacks are 0",
        order = orderBase + 4.3,
        width = 0.7,
        hidden = function()
            if hiddenIfCollapsed() then return true end
            local buff = GetTrackedBuff(index)
            return not buff or (buff.displayType ~= "bar" and buff.displayType ~= "ring")
        end,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.showInCombat
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.showInCombat = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Only In Combat (전투 중에만 표시)
    options["tracked" .. index .. "_onlyInCombat"] = {
        type = "toggle",
        name = "    " .. (L["Only show in combat"] or "Only show in combat"),
        desc = L["Hide when out of combat"] or "Hide when out of combat",
        order = orderBase + 4.4,
        width = 0.7,
        hidden = function()
            if hiddenIfCollapsed() then return true end
            local buff = GetTrackedBuff(index)
            return not buff or (buff.displayType ~= "bar" and buff.displayType ~= "ring" and buff.displayType ~= "text")
        end,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.onlyInCombat
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.onlyInCombat = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Hide from CDM (쿨다운 관리자에서 숨기기) → General 탭
    options["tracked" .. index .. "_hideFromCDM"] = {
        type = "toggle",
        name = "    " .. (L["Hide from CDM"] or "Hide from CDM"),
        desc = L["Hide this buff from Cooldown Manager when tracked (avoids duplication)"] or "Hide this buff from Cooldown Manager when tracked (avoids duplication)",
        order = orderBase + 1.06,  -- [FIX] General 탭(0~1.09) 범위로 이동
        width = 0.7,
        hidden = hiddenIfCollapsed,  -- 모든 displayType에 표시
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.hideFromCDM
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.hideFromCDM = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- ============================================================
    -- ACTIVATION CONDITION (활성조건 - order 1.07 ~ 1.09)
    -- 해당 스킬을 배웠거나, 특정 특성을 배웠을 때만 트래커 활성화
    -- ============================================================

    -- Header
    options["tracked" .. index .. "_activationHeader"] = {
        type = "description",
        name = "\n|cff88ccff━━━ " .. (L["Activation Condition"] or "활성조건") .. " ━━━|r",
        order = orderBase + 1.07,
        width = "full",
        fontSize = "medium",
        hidden = hiddenIfCollapsed,
    }

    -- Activation Type
    options["tracked" .. index .. "_activationType"] = {
        type = "select",
        name = "    " .. (L["Condition Type"] or "조건 유형"),
        desc = (L["Choose when this tracker should be active"] or "이 트래커를 언제 활성화할지 선택합니다"),
        order = orderBase + 1.071,
        width = 0.8,
        hidden = hiddenIfCollapsed,
        values = {
            ["none"] = L["Always Active"] or "항상 활성",
            ["spell"] = L["Spell Known"] or "스킬 습득 시",
            ["talent"] = L["Talent Learned"] or "특성 습득 시",
        },
        sorting = { "none", "spell", "talent" },
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.activationType or "none"
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.activationType = val
                DDingUI:UpdateBuffTrackerBar()
                RefreshOptions()
            end
        end,
    }

    -- Spell Known: spellID input
    options["tracked" .. index .. "_activationSpellID"] = {
        type = "input",
        name = "    " .. (L["Spell ID"] or "스킬 ID"),
        desc = (L["Enter spell ID to check. Leave empty to use cooldownID."] or "확인할 스킬 ID를 입력하세요. 비워두면 cooldownID를 사용합니다."),
        order = orderBase + 1.072,
        width = 0.6,
        hidden = function()
            if hiddenIfCollapsed() then return true end
            local buff = GetTrackedBuff(index)
            return not buff or not buff.settings or buff.settings.activationType ~= "spell"
        end,
        get = function()
            local buff = GetTrackedBuff(index)
            local id = buff and buff.settings and buff.settings.activationSpellID
            if id and id > 0 then return tostring(id) end
            return ""
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.activationSpellID = tonumber(val) or 0
                DDingUI:UpdateBuffTrackerBar()
                RefreshOptions()
            end
        end,
    }

    -- Spell Known: preview
    options["tracked" .. index .. "_activationSpellPreview"] = {
        type = "description",
        name = function()
            local buff = GetTrackedBuff(index)
            local spellID = buff and buff.settings and buff.settings.activationSpellID
            if not spellID or spellID <= 0 then
                spellID = buff and buff.cooldownID or 0
            end
            if spellID and spellID > 0 then
                local name = C_Spell.GetSpellName(spellID)
                local known = IsPlayerSpell(spellID)
                local status = known and "|cff00ff00[O] 습득|r" or "|cffff4444[X] 미습득|r"
                return "    > " .. (name or "?") .. " " .. status
            end
            return "    > (ID 없음)"
        end,
        order = orderBase + 1.073,
        width = "full",
        fontSize = "small",
        hidden = function()
            if hiddenIfCollapsed() then return true end
            local buff = GetTrackedBuff(index)
            return not buff or not buff.settings or buff.settings.activationType ~= "spell"
        end,
    }

    -- Talent: nodeID input
    options["tracked" .. index .. "_activationTalentID"] = {
        type = "input",
        name = "    " .. (L["Talent Node ID"] or "특성 노드 ID"),
        desc = (L["Enter talent node ID. The talent name will be shown for verification."] or "특성 노드 ID를 입력하세요. 확인을 위해 특성 이름이 표시됩니다."),
        order = orderBase + 1.074,
        width = 0.6,
        hidden = function()
            if hiddenIfCollapsed() then return true end
            local buff = GetTrackedBuff(index)
            return not buff or not buff.settings or buff.settings.activationType ~= "talent"
        end,
        get = function()
            local buff = GetTrackedBuff(index)
            local id = buff and buff.settings and buff.settings.activationTalentID
            if id and id > 0 then return tostring(id) end
            return ""
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.activationTalentID = tonumber(val) or 0
                DDingUI:UpdateBuffTrackerBar()
                RefreshOptions()
            end
        end,
    }

    -- Talent: preview
    options["tracked" .. index .. "_activationTalentPreview"] = {
        type = "description",
        name = function()
            local buff = GetTrackedBuff(index)
            local nodeID = buff and buff.settings and buff.settings.activationTalentID
            if nodeID and nodeID > 0 then
                local configID = C_ClassTalents.GetActiveConfigID()
                if configID then
                    local nodeInfo = nil
                    pcall(function() nodeInfo = C_Traits.GetNodeInfo(configID, nodeID) end)
                    if nodeInfo and nodeInfo.entryIDs and #nodeInfo.entryIDs > 0 then
                        local entryInfo = nil
                        pcall(function() entryInfo = C_Traits.GetEntryInfo(configID, nodeInfo.entryIDs[1]) end)
                        local defInfo = entryInfo and entryInfo.definitionID and C_Traits.GetDefinitionInfo(entryInfo.definitionID)
                        local spellName = defInfo and defInfo.spellID and C_Spell.GetSpellName(defInfo.spellID)
                        local rank = nodeInfo.activeRank or 0
                        local maxRank = nodeInfo.maxRanks or 1
                        local status = rank > 0 and ("|cff00ff00[O] " .. rank .. "/" .. maxRank .. "|r") or "|cffff4444[X] 미습득|r"
                        return "    > " .. (spellName or "Node " .. nodeID) .. " " .. status
                    end
                end
                return "    > Node " .. nodeID .. " (조회 불가)"
            end
            return "    > (ID 없음)"
        end,
        order = orderBase + 1.075,
        width = "full",
        fontSize = "small",
        hidden = function()
            if hiddenIfCollapsed() then return true end
            local buff = GetTrackedBuff(index)
            return not buff or not buff.settings or buff.settings.activationType ~= "talent"
        end,
    }

    -- Smooth Animation (bar와 ring)
    options["tracked" .. index .. "_smoothProgress"] = {
        type = "toggle",
        name = "    " .. (L["Smooth Animation"] or "Smooth Animation"),
        desc = L["Smooth bar fill transition"] or "Smooth bar fill transition",
        order = orderBase + 4.55,
        width = 0.7,
        hidden = function()
            if hiddenIfCollapsed() then return true end
            local buff = GetTrackedBuff(index)
            return not buff or (buff.displayType ~= "bar" and buff.displayType ~= "ring")
        end,
        get = function()
            local buff = GetTrackedBuff(index)
            if buff and buff.settings and buff.settings.smoothProgress ~= nil then
                return buff.settings.smoothProgress
            end
            return true  -- default
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.smoothProgress = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Bar Fill Mode (bar mode only)
    options["tracked" .. index .. "_barFillMode"] = {
        type = "select",
        name = "    " .. (L["Bar Fill Mode"] or "Bar Fill Mode"),
        order = orderBase + 4.6,
        width = 0.7,
        hidden = function()
            if hiddenIfNotBar() then return true end
            local buff = GetTrackedBuff(index)
            -- Spell 모드: 항상 쿨다운/충전 기반 fill, 모드 선택 불필요
            if buff and buff.trigger and buff.trigger.type == "spell" then return true end
            return false
        end,
        values = {
            duration = L["Duration"] or "Duration",
        },
        get = function()
            local buff = GetTrackedBuff(index)
            return "duration"  -- 항상 duration (stacks는 시크릿밸류 이슈로 삭제됨)
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.barFillMode = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Max Duration for bar fill (duration mode only)
    options["tracked" .. index .. "_barMaxDuration"] = {
        type = "range",
        name = "    " .. (L["Max Duration (sec)"] or "Max Duration (sec)"),
        desc = L["Maximum duration for manual countdown. Used by duration triggers and ring/bar fill."] or "Maximum duration for manual countdown. Set to 0 to use API duration.",
        order = orderBase + 4.65,
        width = 1.0,
        min = 0, max = 120, step = 0.5,
        hidden = hiddenIfNotDuration,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.maxDuration or 0
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.maxDuration = (val > 0) and val or nil
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Duration Tick Positions (duration mode only)
    -- 사용자가 비율로 tick 위치를 설정 (예: "0.3" = 30%, 팬데믹 기준점)
    options["tracked" .. index .. "_durationTickPositions"] = {
        type = "input",
        name = "    " .. (L["Duration Tick Positions"] or "Duration Tick Positions"),
        desc = (L["Duration Tick Positions Desc"] or "Enter positions as percentages (0-100), separated by commas. Example: 30 for pandemic threshold."),
        order = orderBase + 4.98,
        width = 1.0,
        hidden = hiddenIfNotDuration,
        get = function()
            local buff = GetTrackedBuff(index)
            if buff and buff.settings and buff.settings.durationTickPositions then
                -- 배열을 문자열로 변환 (0.3 -> "30")
                local positions = buff.settings.durationTickPositions
                local strs = {}
                for _, pos in ipairs(positions) do
                    table.insert(strs, tostring(math.floor(pos * 100 + 0.5)))
                end
                return table.concat(strs, ", ")
            end
            return ""
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                -- 문자열을 배열로 파싱 ("30, 50" -> {0.3, 0.5})
                local positions = {}
                for numStr in string.gmatch(val, "([%d%.]+)") do
                    local num = tonumber(numStr)
                    if num then
                        -- 100보다 크면 이미 퍼센트, 아니면 0-1 사이일 수 있음
                        if num > 1 then
                            num = num / 100  -- 30 -> 0.3
                        end
                        if num > 0 and num < 1 then
                            table.insert(positions, num)
                        end
                    end
                end
                -- 정렬
                table.sort(positions)
                trackedBuffs[index].settings.durationTickPositions = positions
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Bar Color (bar mode only, spell 모드에서는 숨김 — display.barColor와 중복)
    options["tracked" .. index .. "_barColor"] = {
        type = "color",
        name = "    " .. (L["Bar Color"] or "Bar Color"),
        order = orderBase + 4.8,
        width = 0.5,
        hasAlpha = true,
        hidden = function()
            if hiddenIfNotBar() then return true end
            -- spell 모드에서는 display.barColor가 있으므로 중복 숨김
            local buff = GetTrackedBuff(index)
            if buff and (buff.trackingMode == "spell" or (buff.trigger and buff.trigger.type == "spell")) then
                return true
            end
            return false
        end,
        get = function()
            local buff = GetTrackedBuff(index)
            if buff and buff.settings and buff.settings.barColor then
                local c = buff.settings.barColor
                return c[1] or 1, c[2] or 0.8, c[3] or 0, c[4] or 1
            end
            return 1, 0.8, 0, 1
        end,
        set = function(_, r, g, b, a)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.barColor = {r, g, b, a}
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- ========== STACKS TEXT SETTINGS (Bar mode only) ==========
    -- Stacks Text Header
    options["tracked" .. index .. "_stacksTextHeader"] = {
        type = "description",
        name = function()
            local buff = GetTrackedBuff(index)
            local isSpell = buff and (buff.trackingMode == "spell" or (buff.trigger and buff.trigger.type == "spell"))
            local label = isSpell and (L["Charge Text"] or "Charge Text") or (L["Stacks Text"] or "Stacks Text")
            return "\n|cffffaa00━━━ " .. label .. " ━━━|r"
        end,
        order = orderBase + 6.0,
        width = "full",
        fontSize = "medium",
        hidden = hiddenIfNotBar,
    }

    -- Show Stacks/Charge Text
    options["tracked" .. index .. "_showStacksText"] = {
        type = "toggle",
        name = function()
            local buff = GetTrackedBuff(index)
            local isSpell = buff and (buff.trackingMode == "spell" or (buff.trigger and buff.trigger.type == "spell"))
            if isSpell then
                return "    " .. (L["Show Charge Text"] or "Show Charge Text")
            end
            return "    " .. (L["Show Stacks Text"] or "Show Stacks Text")
        end,
        order = orderBase + 6.1,
        width = 0.7,
        hidden = hiddenIfNotBar,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.showStacksText
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.showStacksText = val
                DDingUI:UpdateBuffTrackerBar()
                RefreshOptions()  -- 하위 옵션 hidden 상태 즉시 업데이트
            end
        end,
    }

    -- Helper: hidden if stacks text is disabled (bar mode only)
    local function hiddenIfStacksTextOff()
        if hiddenIfNotBar() then return true end
        local buff = GetTrackedBuff(index)
        return not (buff and buff.settings and buff.settings.showStacksText)
    end

    -- Stacks Text Font
    options["tracked" .. index .. "_textFont"] = {
        type = "select",
        name = "        " .. (L["Font"] or "Font"),
        order = orderBase + 6.15,
        width = 1.0,
        dialogControl = "LSM30_Font",
        values = function() return DDingUI:GetFontValues() end,
        hidden = hiddenIfStacksTextOff,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.textFont or DDingUI.db.profile.defaultFont or DDingUI.DEFAULT_FONT_NAME
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.textFont = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Stacks Text Size
    options["tracked" .. index .. "_textSize"] = {
        type = "range",
        name = "        " .. (L["Size"] or "Size"),
        order = orderBase + 6.2,
        width = 0.5,
        min = 6, max = 24, step = 1,
        hidden = hiddenIfStacksTextOff,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.textSize or 12
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.textSize = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Stacks Text Align
    options["tracked" .. index .. "_textAlign"] = {
        type = "select",
        name = "        " .. (L["Align"] or "Align"),
        order = orderBase + 6.3,
        width = 0.5,
        values = {
            ["LEFT"] = L["Left"] or "Left",
            ["CENTER"] = L["Center"] or "Center",
            ["RIGHT"] = L["Right"] or "Right",
        },
        hidden = hiddenIfStacksTextOff,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.textAlign or "CENTER"
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.textAlign = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Stacks Text X Offset
    options["tracked" .. index .. "_textX"] = {
        type = "range",
        name = "        " .. (L["X Offset"] or "X Offset"),
        order = orderBase + 6.4,
        width = 0.5,
        min = -100, max = 100, step = 0.1,
        hidden = hiddenIfStacksTextOff,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.textX or 0
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.textX = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Stacks Text Y Offset
    options["tracked" .. index .. "_textY"] = {
        type = "range",
        name = "        " .. (L["Y Offset"] or "Y Offset"),
        order = orderBase + 6.5,
        width = 0.5,
        min = -100, max = 100, step = 0.1,
        hidden = hiddenIfStacksTextOff,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.textY or 0
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.textY = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Stacks Text Color
    options["tracked" .. index .. "_textColor"] = {
        type = "color",
        name = "        " .. (L["Color"] or "Color"),
        order = orderBase + 6.6,
        width = 0.5,
        hasAlpha = true,
        hidden = hiddenIfStacksTextOff,
        get = function()
            local buff = GetTrackedBuff(index)
            local c = buff and buff.settings and buff.settings.textColor or { 1, 1, 1, 1 }
            return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
        end,
        set = function(_, r, g, b, a)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.textColor = { r, g, b, a }
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Helper: Hide when not bar/icon/text/ring mode (duration text는 이 4가지에서 사용 가능) -- [12.0.1]
    local function hiddenIfNotBarOrIconOrText()
        if hiddenIfCollapsed() then return true end
        local buff = GetTrackedBuff(index)
        if not buff then return true end
        local dt = buff.displayType
        return dt ~= "bar" and dt ~= "icon" and dt ~= "text" and dt ~= "ring"
    end

    -- ========== DURATION TEXT SETTINGS (Bar/Icon/Text mode) ========== -- [12.0.1]
    -- Duration Text Header
    options["tracked" .. index .. "_durationTextHeader"] = {
        type = "description",
        name = function()
            local buff = GetTrackedBuff(index)
            local isSpell = buff and (buff.trackingMode == "spell" or (buff.trigger and buff.trigger.type == "spell"))
            local label = isSpell and (L["Cooldown Text"] or "Cooldown Text") or (L["Duration Text"] or "Duration Text")
            return "\n|cff88ddff━━━ " .. label .. " ━━━|r"
        end,
        order = orderBase + 7.0,
        width = "full",
        fontSize = "medium",
        hidden = hiddenIfNotBarOrIconOrText,
    }

    -- Show Duration/Cooldown Text
    options["tracked" .. index .. "_showDurationText"] = {
        type = "toggle",
        name = function()
            local buff = GetTrackedBuff(index)
            local isSpell = buff and (buff.trackingMode == "spell" or (buff.trigger and buff.trigger.type == "spell"))
            if isSpell then
                return "    " .. (L["Show Cooldown Text"] or "Show Cooldown Text")
            end
            return "    " .. (L["Show Duration Text"] or "Show Duration Text")
        end,
        order = orderBase + 7.1,
        width = 0.7,
        hidden = hiddenIfNotBarOrIconOrText,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.showDurationText
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.showDurationText = val
                DDingUI:UpdateBuffTrackerBar()
                RefreshOptions()  -- 하위 옵션 hidden 상태 즉시 업데이트
            end
        end,
    }

    -- Helper: hidden if duration text is disabled (bar/icon/text mode) -- [12.0.1]
    local function hiddenIfDurationTextOff()
        if hiddenIfNotBarOrIconOrText() then return true end
        local buff = GetTrackedBuff(index)
        return not (buff and buff.settings and buff.settings.showDurationText)
    end

    -- Duration Text Font
    options["tracked" .. index .. "_durationTextFont"] = {
        type = "select",
        name = "        " .. (L["Font"] or "Font"),
        order = orderBase + 7.15,
        width = 1.0,
        dialogControl = "LSM30_Font",
        values = function() return DDingUI:GetFontValues() end,
        hidden = hiddenIfDurationTextOff,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.durationTextFont or DDingUI.db.profile.defaultFont or DDingUI.DEFAULT_FONT_NAME
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.durationTextFont = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Duration Text Size
    options["tracked" .. index .. "_durationTextSize"] = {
        type = "range",
        name = "        " .. (L["Size"] or "Size"),
        order = orderBase + 7.2,
        width = 0.5,
        min = 6, max = 24, step = 1,
        hidden = hiddenIfDurationTextOff,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.durationTextSize or 10
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.durationTextSize = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Duration Text Align
    options["tracked" .. index .. "_durationTextAlign"] = {
        type = "select",
        name = "        " .. (L["Align"] or "Align"),
        order = orderBase + 7.3,
        width = 0.5,
        values = {
            ["LEFT"] = L["Left"] or "Left",
            ["CENTER"] = L["Center"] or "Center",
            ["RIGHT"] = L["Right"] or "Right",
        },
        hidden = hiddenIfDurationTextOff,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.durationTextAlign or "CENTER"
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.durationTextAlign = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Duration Text X Offset
    options["tracked" .. index .. "_durationTextX"] = {
        type = "range",
        name = "        " .. (L["X Offset"] or "X Offset"),
        order = orderBase + 7.4,
        width = 0.5,
        min = -100, max = 100, step = 0.1,
        hidden = hiddenIfDurationTextOff,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.durationTextX or 0
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.durationTextX = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Duration Text Y Offset
    options["tracked" .. index .. "_durationTextY"] = {
        type = "range",
        name = "        " .. (L["Y Offset"] or "Y Offset"),
        order = orderBase + 7.5,
        width = 0.5,
        min = -100, max = 100, step = 0.1,
        hidden = hiddenIfDurationTextOff,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.durationTextY or 0
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.durationTextY = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Duration Text Color
    options["tracked" .. index .. "_durationTextColor"] = {
        type = "color",
        name = "        " .. (L["Color"] or "Color"),
        order = orderBase + 7.6,
        width = 0.5,
        hasAlpha = true,
        hidden = hiddenIfDurationTextOff,
        get = function()
            local buff = GetTrackedBuff(index)
            local c = buff and buff.settings and buff.settings.durationTextColor or { 1, 1, 1, 1 }
            return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
        end,
        set = function(_, r, g, b, a)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.durationTextColor = { r, g, b, a }
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Duration Decimals (소수점 자릿수)
    options["tracked" .. index .. "_durationDecimals"] = {
        type = "range",
        name = "        " .. (L["Decimal Places"] or "Decimal Places"),
        desc = L["Number of decimal places for duration display"] or "Number of decimal places for duration display",
        order = orderBase + 7.7,
        width = 0.5,
        min = 0, max = 2, step = 1,
        hidden = hiddenIfDurationTextOff,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.durationDecimals or 1
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.durationDecimals = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Duration Warning Enable
    options["tracked" .. index .. "_durationWarningEnabled"] = {
        type = "toggle",
        name = "        " .. (L["Warning Color"] or "Warning Color"),
        desc = L["Change text color when duration is low"] or "Change text color when duration is low",
        order = orderBase + 7.75,
        width = 0.6,
        hidden = hiddenIfDurationTextOff,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.durationWarningEnabled or false
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.durationWarningEnabled = val
                DDingUI:UpdateBuffTrackerBar()
                RefreshOptions()  -- 하위 옵션 hidden 상태 즉시 업데이트
            end
        end,
    }

    -- Duration Warning Threshold
    local function hiddenIfWarningOff()
        if hiddenIfDurationTextOff() then return true end
        local buff = GetTrackedBuff(index)
        return not buff or not buff.settings or not buff.settings.durationWarningEnabled
    end

    options["tracked" .. index .. "_durationWarningThreshold"] = {
        type = "range",
        name = "            " .. (L["Threshold (sec)"] or "Threshold (sec)"),
        desc = L["Change color when remaining time is below this value"] or "Change color when remaining time is below this value",
        order = orderBase + 7.76,
        width = 0.5,
        min = 1, max = 30, step = 1,
        hidden = hiddenIfWarningOff,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.durationWarningThreshold or 5
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.durationWarningThreshold = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Duration Warning Color
    options["tracked" .. index .. "_durationWarningColor"] = {
        type = "color",
        name = "            " .. (L["Warning Color"] or "Warning Color"),
        order = orderBase + 7.77,
        width = 0.5,
        hasAlpha = true,
        hidden = hiddenIfWarningOff,
        get = function()
            local buff = GetTrackedBuff(index)
            local c = buff and buff.settings and buff.settings.durationWarningColor or { 1, 0.2, 0.2, 1 }
            return c[1] or 1, c[2] or 0.2, c[3] or 0.2, c[4] or 1
        end,
        set = function(_, r, g, b, a)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.durationWarningColor = { r, g, b, a }
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Tick Settings Header
    options["tracked" .. index .. "_tickHeader"] = {
        type = "description",
        name = "\n|cffff88ff━━━ " .. (L["Tick Settings"] or "Tick Settings") .. " ━━━|r",
        order = orderBase + 5.95,
        width = "full",
        fontSize = "medium",
        hidden = function()
            if hiddenIfNotBar() then return true end
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.barFillMode == "duration"
        end,
    }

    -- Show Ticks (bar mode only, stacks mode)
    options["tracked" .. index .. "_showTicks"] = {
        type = "toggle",
        name = "    " .. (L["Show Ticks"] or "Show Ticks"),
        desc = L["Show segment markers between stacks"] or "Show segment markers between stacks",
        order = orderBase + 5.96,
        width = 0.7,
        hidden = function()
            if hiddenIfNotBar() then return true end
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.barFillMode == "duration"
        end,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.showTicks ~= false
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.showTicks = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Tick Width (bar mode only, stacks mode)
    options["tracked" .. index .. "_tickWidth"] = {
        type = "range",
        name = "    " .. (L["Tick Width"] or "Tick Width"),
        order = orderBase + 5.97,
        width = 0.7,
        min = 1, max = 10, step = 1,
        hidden = function()
            if hiddenIfNotBar() then return true end
            local buff = GetTrackedBuff(index)
            if buff and buff.settings then
                if buff.settings.barFillMode == "duration" then return true end
                if buff.settings.showTicks == false then return true end
            end
            return false
        end,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.tickWidth or 2
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.tickWidth = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Position header (bar mode only)
    options["tracked" .. index .. "_posHeader"] = {
        type = "description",
        name = "    |cffffcc00" .. (L["Bar Position"] or "Bar Position") .. "|r",
        order = orderBase + 5.0,
        width = "full",
        fontSize = "medium",
        hidden = hiddenIfNotBar,
    }

    -- Attach To (bar mode only)
    options["tracked" .. index .. "_attachTo"] = {
        type = "select",
        name = "    " .. (L["Attach To"] or "Attach To"),
        desc = L["Attach To Desc"] or "Select the frame to attach this bar to",
        order = orderBase + 5.1,
        width = 0.8,
        hidden = hiddenIfNotBar,
        values = function()
            -- [FIX] 하드코딩 → GetViewerOptions() 사용 (CastBar, GroupSystem 그룹 등 포함)
            local frames = {
                ["UIParent"] = "UIParent",
                ["PlayerFrame"] = "PlayerFrame",
            }
            -- GetViewerOptions()로 뷰어/리소스바/캐스트바/그룹 등 모두 포함
            if DDingUI.GetViewerOptions then
                for k, v in pairs(DDingUI:GetViewerOptions()) do
                    frames[k] = v
                end
            end
            -- 추가 프레임 (GetViewerOptions에 없는 것들)
            if _G["DDingUIResourceBarFrame"] then
                frames["DDingUIResourceBarFrame"] = "Resource Bar"
            end
            if _G["DDingUIComboPointsFrame"] then
                frames["DDingUIComboPointsFrame"] = "Combo Points"
            end
            if _G["DDingUIHealthBarFrame"] then
                frames["DDingUIHealthBarFrame"] = "Health Bar"
            end
            -- 커스텀 값
            local buff = GetTrackedBuff(index)
            local current = buff and buff.settings and buff.settings.attachTo
            if current and not frames[current] then
                frames[current] = current .. " (Custom)"
            end
            return frames
        end,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.attachTo or defaultSpecConfig.attachTo
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.attachTo = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Pick Frame Button (bar mode only)
    options["tracked" .. index .. "_pickFrame"] = {
        type = "execute",
        name = L["Pick"] or "선택",
        order = orderBase + 5.15,
        width = 0.4,
        hidden = hiddenIfNotBar,
        func = function()
            DDingUI:StartFramePicker(function(frameName)
                if frameName then
                    local trackedBuffs = GetTrackedBuffs()
                    if trackedBuffs[index] and trackedBuffs[index].settings then
                        trackedBuffs[index].settings.attachTo = frameName
                        DDingUI:UpdateBuffTrackerBar()
                    end
                end
            end)
        end,
    }

    -- Anchor Point (bar mode only)
    options["tracked" .. index .. "_anchorPoint"] = {
        type = "select",
        name = "    " .. (L["Anchor Point"] or "Anchor Point"),
        desc = L["Anchor Point Desc"] or "Select the anchor point on the target frame",
        order = orderBase + 5.2,
        width = 0.7,
        hidden = hiddenIfNotBar,
        values = {
            ["TOP"] = L["Top"] or "Top",
            ["BOTTOM"] = L["Bottom"] or "Bottom",
            ["LEFT"] = L["Left"] or "Left",
            ["RIGHT"] = L["Right"] or "Right",
            ["CENTER"] = L["Center"] or "Center",
            ["TOPLEFT"] = L["Top Left"] or "Top Left",
            ["TOPRIGHT"] = L["Top Right"] or "Top Right",
            ["BOTTOMLEFT"] = L["Bottom Left"] or "Bottom Left",
            ["BOTTOMRIGHT"] = L["Bottom Right"] or "Bottom Right",
        },
        get = function()
            local buff = GetTrackedBuff(index)
            local globalAnchor = DDingUI.db and DDingUI.db.profile.buffTrackerBar and DDingUI.db.profile.buffTrackerBar.anchorPoint or "BOTTOM"
            return buff and buff.settings and buff.settings.anchorPoint or globalAnchor
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.anchorPoint = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Self Point / 기준점 (bar mode only)
    options["tracked" .. index .. "_selfPoint"] = {
        type = "select",
        name = "    " .. (L["Self Point"] or "기준점"),
        desc = L["Which point of the bar itself is used for anchoring"] or "바 자체의 어느 지점을 기준으로 앵커링할지 설정",
        order = orderBase + 5.25,
        width = 0.7,
        hidden = hiddenIfNotBar,
        values = {
            ["TOP"] = L["Top"] or "Top",
            ["BOTTOM"] = L["Bottom"] or "Bottom",
            ["LEFT"] = L["Left"] or "Left",
            ["RIGHT"] = L["Right"] or "Right",
            ["CENTER"] = L["Center"] or "Center",
            ["TOPLEFT"] = L["Top Left"] or "Top Left",
            ["TOPRIGHT"] = L["Top Right"] or "Top Right",
            ["BOTTOMLEFT"] = L["Bottom Left"] or "Bottom Left",
            ["BOTTOMRIGHT"] = L["Bottom Right"] or "Bottom Right",
        },
        get = function()
            local buff = GetTrackedBuff(index)
            local globalSelfPoint = DDingUI.db and DDingUI.db.profile.buffTrackerBar and DDingUI.db.profile.buffTrackerBar.selfPoint or "CENTER"
            return buff and buff.settings and buff.settings.selfPoint or globalSelfPoint
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.selfPoint = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Offset X (bar mode only)
    options["tracked" .. index .. "_offsetX"] = {
        type = "range",
        name = "    " .. (L["Offset X"] or "Offset X"),
        order = orderBase + 5.3,
        width = 0.7,
        min = -500, max = 500, step = 0.1,
        hidden = hiddenIfNotBar,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.offsetX or 0
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.offsetX = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Offset Y (bar mode only)
    options["tracked" .. index .. "_offsetY"] = {
        type = "range",
        name = "    " .. (L["Offset Y"] or "Offset Y"),
        order = orderBase + 5.4,
        width = 0.7,
        min = -500, max = 500, step = 0.1,
        hidden = hiddenIfNotBar,
        get = function()
            local buff = GetTrackedBuff(index)
            -- Default: stack vertically (each bar 20px below previous)
            local defaultY = (DDingUI.db and DDingUI.db.profile.buffTrackerBar.offsetY or 18) - ((index - 1) * 20)
            return buff and buff.settings and buff.settings.offsetY or defaultY
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.offsetY = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Width (bar mode only)
    options["tracked" .. index .. "_width"] = {
        type = "range",
        name = "    " .. (L["Width"] or "Width"),
        desc = L["0 = auto width"] or "0 = auto width",
        order = orderBase + 5.5,
        width = 0.7,
        min = 0, max = 500, step = 1,
        hidden = hiddenIfNotBar,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.width or 0
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.width = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Height (bar mode only)
    options["tracked" .. index .. "_height"] = {
        type = "range",
        name = "    " .. (L["Height"] or "Height"),
        order = orderBase + 5.6,
        width = 0.7,
        min = 1, max = 50, step = 1,
        hidden = hiddenIfNotBar,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.height or (DDingUI.db and DDingUI.db.profile.buffTrackerBar.height or 4)
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.height = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Bar Orientation (bar mode only)
    options["tracked" .. index .. "_barOrientation"] = {
        type = "select",
        name = "    " .. (L["Bar Direction"] or "바 방향"),
        desc = L["Set bar fill direction"] or "바 채움 방향 설정",
        order = orderBase + 5.65,
        width = 0.7,
        values = {
            ["HORIZONTAL"] = L["Horizontal"] or "수평",
            ["VERTICAL"] = L["Vertical"] or "수직",
        },
        hidden = hiddenIfNotBar,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.barOrientation or "HORIZONTAL"
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.barOrientation = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Bar Reverse Fill (bar mode only)
    options["tracked" .. index .. "_barReverseFill"] = {
        type = "toggle",
        name = "    " .. (L["Reverse Fill"] or "반대로 채우기"),
        desc = L["Fill bar from right to left (horizontal) or top to bottom (vertical)"] or "바를 반대 방향으로 채웁니다 (우→좌 또는 상→하)",
        order = orderBase + 5.66,
        width = 0.7,
        hidden = hiddenIfNotBar,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.barReverseFill or false
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.barReverseFill = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- ============================================================
    -- RING MODE OPTIONS (order 6.0 ~ 6.9)
    -- ============================================================

    -- Ring Header
    options["tracked" .. index .. "_ringHeader"] = {
        type = "description",
        name = "|cffffcc00" .. (L["Ring Settings"] or "링 설정") .. "|r",
        order = orderBase + 6.0,
        width = "full",
        fontSize = "medium",
        hidden = hiddenIfNotRing,
    }

    -- Ring Size
    options["tracked" .. index .. "_ringSize"] = {
        type = "range",
        name = "    " .. (L["Ring Size"] or "링 크기"),
        order = orderBase + 6.1,
        width = 0.7,
        min = 16, max = 128, step = 1,
        hidden = hiddenIfNotRing,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.ringSize or 32
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.ringSize = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Ring Thickness (texture selection)
    options["tracked" .. index .. "_ringThickness"] = {
        type = "select",
        name = "    " .. (L["Ring Thickness"] or "링 두께"),
        desc = L["Select ring thickness (changes texture)"] or "링 두께를 선택합니다 (텍스쳐 변경)",
        order = orderBase + 6.12,
        width = 0.7,
        hidden = hiddenIfNotRing,
        values = {
            [10] = "10px",
            [20] = "20px",
            [30] = "30px",
            [40] = "40px",
        },
        sorting = { 10, 20, 30, 40 },
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.ringThickness or 20
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.ringThickness = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Ring Fill Mode: 링은 항상 duration 모드 (드롭다운 제거됨)

    -- Ring Reverse (reverse fill direction)
    options["tracked" .. index .. "_ringReverse"] = {
        type = "toggle",
        name = "    " .. (L["Reverse Fill"] or "반대로 채우기"),
        desc = L["Fill ring in reverse direction"] or "링을 반대 방향으로 채웁니다",
        order = orderBase + 6.2,
        width = 0.7,
        hidden = hiddenIfNotRing,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.ringReverse or false
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.ringReverse = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Ring Color
    options["tracked" .. index .. "_ringColor"] = {
        type = "color",
        name = "    " .. (L["Ring Color"] or "링 색상"),
        order = orderBase + 6.3,
        width = 0.7,
        hasAlpha = true,
        hidden = hiddenIfNotRing,
        get = function()
            local buff = GetTrackedBuff(index)
            local color = buff and buff.settings and buff.settings.ringColor
            if color then
                return color[1], color[2], color[3], color[4] or 1
            end
            return 1, 0.8, 0, 1
        end,
        set = function(_, r, g, b, a)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.ringColor = { r, g, b, a }
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Ring Background Color
    options["tracked" .. index .. "_ringBgColor"] = {
        type = "color",
        name = "    " .. (L["Ring Background"] or "링 배경색"),
        order = orderBase + 6.35,
        width = 0.7,
        hasAlpha = true,
        hidden = hiddenIfNotRing,
        get = function()
            local buff = GetTrackedBuff(index)
            local color = buff and buff.settings and buff.settings.ringBgColor
            if color then
                return color[1], color[2], color[3], color[4] or 1
            end
            return 0.15, 0.15, 0.15, 1
        end,
        set = function(_, r, g, b, a)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.ringBgColor = { r, g, b, a }
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Ring Border Size
    options["tracked" .. index .. "_ringBorderSize"] = {
        type = "range",
        name = "    " .. (L["Ring Border Size"] or "링 테두리 크기"),
        order = orderBase + 6.4,
        width = 0.7,
        min = 0, max = 8, step = 1,
        hidden = hiddenIfNotRing,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.ringBorderSize or 2
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.ringBorderSize = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Ring Border Color
    options["tracked" .. index .. "_ringBorderColor"] = {
        type = "color",
        name = "    " .. (L["Ring Border Color"] or "링 테두리 색상"),
        order = orderBase + 6.45,
        width = 0.7,
        hasAlpha = true,
        hidden = hiddenIfNotRing,
        get = function()
            local buff = GetTrackedBuff(index)
            local color = buff and buff.settings and buff.settings.ringBorderColor
            if color then
                return color[1], color[2], color[3], color[4] or 1
            end
            return 0, 0, 0, 1
        end,
        set = function(_, r, g, b, a)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.ringBorderColor = { r, g, b, a }
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Ring Show Text
    options["tracked" .. index .. "_ringShowText"] = {
        type = "toggle",
        name = "    " .. (L["Show Text"] or "텍스트 표시"),
        order = orderBase + 6.5,
        width = 0.7,
        hidden = hiddenIfNotRing,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.ringShowText ~= false
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.ringShowText = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Ring Text Size
    options["tracked" .. index .. "_ringTextSize"] = {
        type = "range",
        name = "    " .. (L["Text Size"] or "텍스트 크기"),
        order = orderBase + 6.55,
        width = 0.7,
        min = 6, max = 32, step = 1,
        hidden = function()
            if hiddenIfNotRing() then return true end
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.ringShowText == false
        end,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.ringTextSize or 12
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.ringTextSize = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Ring Position Header
    options["tracked" .. index .. "_ringPosHeader"] = {
        type = "description",
        name = "    |cff888888" .. (L["Position"] or "위치") .. "|r",
        order = orderBase + 6.6,
        width = "full",
        fontSize = "small",
        hidden = hiddenIfNotRing,
    }

    -- Ring Offset X
    options["tracked" .. index .. "_ringOffsetX"] = {
        type = "range",
        name = "    " .. (L["X Offset"] or "X 오프셋"),
        order = orderBase + 6.65,
        width = 0.7,
        min = -500, max = 500, step = 1,
        hidden = hiddenIfNotRing,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.ringOffsetX or 0
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.ringOffsetX = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Ring Offset Y
    options["tracked" .. index .. "_ringOffsetY"] = {
        type = "range",
        name = "    " .. (L["Y Offset"] or "Y 오프셋"),
        order = orderBase + 6.7,
        width = 0.7,
        min = -500, max = 500, step = 1,
        hidden = hiddenIfNotRing,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.ringOffsetY or 0
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.ringOffsetY = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Border header (bar mode only)
    options["tracked" .. index .. "_borderHeader"] = {
        type = "description",
        name = "    |cffffcc00" .. (L["Bar Border"] or "Bar Border") .. "|r",
        order = orderBase + 5.7,
        width = "full",
        fontSize = "medium",
        hidden = hiddenIfNotBar,
    }

    -- Border Size (bar mode only)
    options["tracked" .. index .. "_borderSize"] = {
        type = "range",
        name = "    " .. (L["Border Size"] or "Border Size"),
        order = orderBase + 5.8,
        width = 0.7,
        min = 0, max = 5, step = 1,
        hidden = hiddenIfNotBar,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.borderSize or (DDingUI.db and DDingUI.db.profile.buffTrackerBar.borderSize or 1)
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.borderSize = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Border Color (bar mode only)
    options["tracked" .. index .. "_borderColor"] = {
        type = "color",
        name = "    " .. (L["Border Color"] or "Border Color"),
        order = orderBase + 5.9,
        width = 0.5,
        hasAlpha = true,
        hidden = hiddenIfNotBar,
        get = function()
            local buff = GetTrackedBuff(index)
            if buff and buff.settings and buff.settings.borderColor then
                local c = buff.settings.borderColor
                return c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1
            end
            local globalCfg = DDingUI.db and DDingUI.db.profile.buffTrackerBar
            if globalCfg and globalCfg.borderColor then
                local c = globalCfg.borderColor
                return c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1
            end
            return 0, 0, 0, 1
        end,
        set = function(_, r, g, b, a)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.borderColor = {r, g, b, a}
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Bar Texture (bar mode only) - LSM:List returns sorted list
    options["tracked" .. index .. "_texture"] = {
        type = "select",
        name = "    " .. (L["Texture"] or "Texture"),
        order = orderBase + 5.91,
        width = 1.0,
        values = function()
            local values = {}
            local list = LSM:List("statusbar")
            for _, name in ipairs(list) do
                values[name] = name
            end
            return values
        end,
        sorting = function()
            return LSM:List("statusbar")
        end,
        hidden = hiddenIfNotBar,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.texture or "Default"
        end,
        set = function(_, val)
            local trackedBuffs = GetTrackedBuffs()
            if trackedBuffs[index] and trackedBuffs[index].settings then
                trackedBuffs[index].settings.texture = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- ============================================================
    -- ALERT SYSTEM OPTIONS (트리거-액션 알림 설정)
    -- Sound mode에서는 숨김 (Sound mode는 별도 사운드 시스템 사용)
    -- ============================================================

    local MAX_ALERT_TRIGGERS = 5
    local MAX_ALERT_ACTIONS = 5

    local function hiddenIfSoundMode()
        if hiddenIfCollapsed() then return true end
        local buff = GetTrackedBuff(index)
        return buff and buff.displayType == "sound"
    end

    local function hiddenIfAlertsOff()
        if hiddenIfSoundMode() then return true end
        local buff = GetTrackedBuff(index)
        if not buff or not buff.settings then return true end
        local alerts = buff.settings.alerts
        return not alerts or not alerts.enabled
    end

    -- Ensure alerts table exists
    local function EnsureAlerts(idx)
        local trackedBuffs = GetTrackedBuffs()
        local buff = trackedBuffs[idx]
        if buff and buff.settings then
            if not buff.settings.alerts then
                buff.settings.alerts = { enabled = false, triggerLogic = "or", triggers = {}, actions = {} }
            end
            if not buff.settings.alerts.triggers then
                buff.settings.alerts.triggers = {}
            end
            if not buff.settings.alerts.actions then
                buff.settings.alerts.actions = {}
            end
            return buff.settings.alerts
        end
        return nil
    end

    -- Alert Header
    options["tracked" .. index .. "_alertHeader"] = {
        type = "description",
        name = "\n|cffff88ff━━━ " .. (L["Conditional Actions"] or "Conditional Actions") .. " ━━━|r",
        order = orderBase + 8.0,
        width = "full",
        fontSize = "medium",
        hidden = hiddenIfSoundMode,
    }

    -- Alerts Enabled toggle
    options["tracked" .. index .. "_alertEnabled"] = {
        type = "toggle",
        name = "    " .. (L["Enable Actions"] or "Enable Actions"),
        desc = L["Enable trigger-action alert system"] or "Enable trigger-action system",
        order = orderBase + 8.01,
        width = 0.8,
        hidden = hiddenIfSoundMode,
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.alerts and buff.settings.alerts.enabled
        end,
        set = function(_, val)
            local alerts = EnsureAlerts(index)
            if alerts then
                alerts.enabled = val
                DDingUI:UpdateBuffTrackerBar()
                RefreshOptions()
            end
        end,
    }

    -- Trigger Logic select (AND/OR)
    options["tracked" .. index .. "_alertTriggerLogic"] = {
        type = "select",
        name = "    " .. (L["Trigger Logic"] or "Trigger Logic"),
        desc = L["How triggers combine: AND = all must be true, OR = any one is enough"] or "How triggers combine: AND = all must be true, OR = any one is enough",
        order = orderBase + 8.02,
        width = 0.5,
        hidden = hiddenIfAlertsOff,
        values = {
            ["or"] = "OR",
            ["and"] = "AND",
        },
        get = function()
            local buff = GetTrackedBuff(index)
            return buff and buff.settings and buff.settings.alerts and buff.settings.alerts.triggerLogic or "or"
        end,
        set = function(_, val)
            local alerts = EnsureAlerts(index)
            if alerts then
                alerts.triggerLogic = val
                DDingUI:UpdateBuffTrackerBar()
            end
        end,
    }

    -- Trigger slots (5 max)
    for trigIdx = 1, MAX_ALERT_TRIGGERS do
        local trigOrderBase = orderBase + 8.10 + (trigIdx - 1) * 0.05

        local function hiddenIfTriggerNotExists()
            if hiddenIfAlertsOff() then return true end
            local buff = GetTrackedBuff(index)
            local triggers = buff and buff.settings and buff.settings.alerts and buff.settings.alerts.triggers
            return not triggers or not triggers[trigIdx]
        end

        -- Trigger type select
        options["tracked" .. index .. "_alertT" .. trigIdx .. "_type"] = {
            type = "select",
            name = "    T" .. trigIdx,
            order = trigOrderBase,
            width = 0.45,
            hidden = hiddenIfTriggerNotExists,
            values = {
                duration = L["Duration"] or "Duration",
                stacks = L["Stacks"] or "Stacks",
                active = L["Active"] or "Active",
            },
            get = function()
                local buff = GetTrackedBuff(index)
                local t = buff and buff.settings and buff.settings.alerts and buff.settings.alerts.triggers and buff.settings.alerts.triggers[trigIdx]
                return t and t.type or "active"
            end,
            set = function(_, val)
                local alerts = EnsureAlerts(index)
                if alerts and alerts.triggers[trigIdx] then
                    alerts.triggers[trigIdx].type = val
                    if val == "active" then
                        alerts.triggers[trigIdx].value = true
                        alerts.triggers[trigIdx].op = "=="
                    elseif val == "duration" then
                        alerts.triggers[trigIdx].value = 5
                        alerts.triggers[trigIdx].op = "<="
                    elseif val == "stacks" then
                        alerts.triggers[trigIdx].value = 3
                        alerts.triggers[trigIdx].op = "<="
                    end
                    DDingUI:UpdateBuffTrackerBar()
                    RefreshOptions()
                end
            end,
        }

        -- Trigger operator select
        options["tracked" .. index .. "_alertT" .. trigIdx .. "_op"] = {
            type = "select",
            name = "",
            order = trigOrderBase + 0.01,
            width = 0.25,
            hidden = hiddenIfTriggerNotExists,
            values = function()
                local buff = GetTrackedBuff(index)
                local t = buff and buff.settings and buff.settings.alerts and buff.settings.alerts.triggers and buff.settings.alerts.triggers[trigIdx]
                if t and t.type == "active" then
                    return { ["=="] = "=", ["!="] = "!=" }
                end
                return { ["<="] = "<=", [">="] = ">=", ["=="] = "=", ["!="] = "!=", ["<"] = "<", [">"] = ">" }
            end,
            get = function()
                local buff = GetTrackedBuff(index)
                local t = buff and buff.settings and buff.settings.alerts and buff.settings.alerts.triggers and buff.settings.alerts.triggers[trigIdx]
                return t and t.op or "<="
            end,
            set = function(_, val)
                local alerts = EnsureAlerts(index)
                if alerts and alerts.triggers[trigIdx] then
                    alerts.triggers[trigIdx].op = val
                    DDingUI:UpdateBuffTrackerBar()
                end
            end,
        }

        -- Trigger value (range for duration/stacks)
        options["tracked" .. index .. "_alertT" .. trigIdx .. "_value"] = {
            type = "range",
            name = "",
            order = trigOrderBase + 0.02,
            width = 0.4,
            min = 0, max = 60, step = 1,
            hidden = function()
                if hiddenIfTriggerNotExists() then return true end
                local buff = GetTrackedBuff(index)
                local t = buff and buff.settings and buff.settings.alerts and buff.settings.alerts.triggers and buff.settings.alerts.triggers[trigIdx]
                return t and t.type == "active"
            end,
            get = function()
                local buff = GetTrackedBuff(index)
                local t = buff and buff.settings and buff.settings.alerts and buff.settings.alerts.triggers and buff.settings.alerts.triggers[trigIdx]
                return t and t.value or 5
            end,
            set = function(_, val)
                local alerts = EnsureAlerts(index)
                if alerts and alerts.triggers[trigIdx] then
                    alerts.triggers[trigIdx].value = val
                    DDingUI:UpdateBuffTrackerBar()
                end
            end,
        }

        -- Trigger active value select (Active/Inactive)
        options["tracked" .. index .. "_alertT" .. trigIdx .. "_activeVal"] = {
            type = "select",
            name = "",
            order = trigOrderBase + 0.02,
            width = 0.4,
            hidden = function()
                if hiddenIfTriggerNotExists() then return true end
                local buff = GetTrackedBuff(index)
                local t = buff and buff.settings and buff.settings.alerts and buff.settings.alerts.triggers and buff.settings.alerts.triggers[trigIdx]
                return not t or t.type ~= "active"
            end,
            values = { ["true"] = L["Active"] or "Active", ["false"] = L["Inactive"] or "Inactive" },
            get = function()
                local buff = GetTrackedBuff(index)
                local t = buff and buff.settings and buff.settings.alerts and buff.settings.alerts.triggers and buff.settings.alerts.triggers[trigIdx]
                return t and tostring(t.value) or "true"
            end,
            set = function(_, val)
                local alerts = EnsureAlerts(index)
                if alerts and alerts.triggers[trigIdx] then
                    alerts.triggers[trigIdx].value = (val == "true")
                    DDingUI:UpdateBuffTrackerBar()
                end
            end,
        }

        -- Remove trigger button
        options["tracked" .. index .. "_alertT" .. trigIdx .. "_remove"] = {
            type = "execute",
            name = "|cffff4444X|r",
            order = trigOrderBase + 0.03,
            width = 0.15,
            hidden = hiddenIfTriggerNotExists,
            func = function()
                local alerts = EnsureAlerts(index)
                if alerts and alerts.triggers then
                    table.remove(alerts.triggers, trigIdx)
                    DDingUI:UpdateBuffTrackerBar()
                    RefreshOptions()
                end
            end,
        }
    end

    -- Add Trigger button
    options["tracked" .. index .. "_alertAddTrigger"] = {
        type = "execute",
        name = "+ " .. (L["Add Trigger"] or "Add Trigger"),
        order = orderBase + 8.40,
        width = 0.6,
        hidden = function()
            if hiddenIfAlertsOff() then return true end
            local buff = GetTrackedBuff(index)
            local triggers = buff and buff.settings and buff.settings.alerts and buff.settings.alerts.triggers or {}
            return #triggers >= MAX_ALERT_TRIGGERS
        end,
        func = function()
            local alerts = EnsureAlerts(index)
            if alerts then
                table.insert(alerts.triggers, { type = "active", op = "==", value = true })
                DDingUI:UpdateBuffTrackerBar()
                RefreshOptions()
            end
        end,
    }

    -- Actions Header
    options["tracked" .. index .. "_alertActionsHeader"] = {
        type = "description",
        name = "\n|cff88ccff" .. (L["Actions"] or "Actions") .. "|r",
        order = orderBase + 8.45,
        width = "full",
        hidden = hiddenIfAlertsOff,
    }

    -- Action type display names
    local actionTypeDisplayNames = {
        color = L["Color"] or "Color",
        sound = L["Sound"] or "Sound",
    }

    -- Action slots (5 max) — 폴더블 inline group
    for actIdx = 1, MAX_ALERT_ACTIONS do
        local actOrderBase = orderBase + 8.50 + (actIdx - 1) * 0.08

        local function hiddenIfActionNotExists()
            if hiddenIfAlertsOff() then return true end
            local buff = GetTrackedBuff(index)
            local actions = buff and buff.settings and buff.settings.alerts and buff.settings.alerts.actions
            return not actions or not actions[actIdx]
        end

        -- 각 동작의 세부 옵션을 inline group args로
        local actionArgs = {}

        -- Action type select
        actionArgs["type"] = {
            type = "select",
            name = L["Type"] or "Type",
            order = 1, width = 0.4,
            values = {
                color = L["Color"] or "Color",
                sound = L["Sound"] or "Sound",
            },
            get = function()
                local buff = GetTrackedBuff(index)
                local a = buff and buff.settings and buff.settings.alerts and buff.settings.alerts.actions and buff.settings.alerts.actions[actIdx]
                return a and a.type or "color"
            end,
            set = function(_, val)
                local alerts = EnsureAlerts(index)
                if alerts and alerts.actions[actIdx] then
                    alerts.actions[actIdx].type = val
                    if val == "color" then
                        alerts.actions[actIdx].color = alerts.actions[actIdx].color or { 1, 0, 0, 1 }
                    elseif val == "sound" then
                        alerts.actions[actIdx].soundFile = alerts.actions[actIdx].soundFile or "None"
                        alerts.actions[actIdx].soundCustomPath = alerts.actions[actIdx].soundCustomPath or ""
                        alerts.actions[actIdx].soundChannel = alerts.actions[actIdx].soundChannel or "Master"
                        alerts.actions[actIdx].soundMode = alerts.actions[actIdx].soundMode or "once"
                        alerts.actions[actIdx].soundCooldown = alerts.actions[actIdx].soundCooldown or 3
                    end
                    DDingUI:UpdateBuffTrackerBar()
                    RefreshOptions()
                end
            end,
        }

        -- Action condition select
        actionArgs["condition"] = {
            type = "select",
            name = L["Condition"] or "Condition",
            order = 2, width = 0.4,
            values = function()
                local vals = { any = L["Any Trigger"] or "Any Trigger" }
                local buff = GetTrackedBuff(index)
                local triggers = buff and buff.settings and buff.settings.alerts and buff.settings.alerts.triggers or {}
                for i = 1, #triggers do
                    vals["trigger" .. i] = "T" .. i .. " (" .. (triggers[i].type or "?") .. ")"
                end
                return vals
            end,
            get = function()
                local buff = GetTrackedBuff(index)
                local a = buff and buff.settings and buff.settings.alerts and buff.settings.alerts.actions and buff.settings.alerts.actions[actIdx]
                return a and a.condition or "any"
            end,
            set = function(_, val)
                local alerts = EnsureAlerts(index)
                if alerts and alerts.actions[actIdx] then
                    alerts.actions[actIdx].condition = val
                    DDingUI:UpdateBuffTrackerBar()
                end
            end,
        }

        -- Color picker (color action only)
        actionArgs["color"] = {
            type = "color",
            name = L["Color"] or "Color",
            order = 3, width = 0.2,
            hasAlpha = true,
            hidden = function()
                local buff = GetTrackedBuff(index)
                local a = buff and buff.settings and buff.settings.alerts and buff.settings.alerts.actions and buff.settings.alerts.actions[actIdx]
                return not a or a.type ~= "color"
            end,
            get = function()
                local buff = GetTrackedBuff(index)
                local a = buff and buff.settings and buff.settings.alerts and buff.settings.alerts.actions and buff.settings.alerts.actions[actIdx]
                local c = a and a.color or { 1, 0, 0, 1 }
                return c[1] or 1, c[2] or 0, c[3] or 0, c[4] or 1
            end,
            set = function(_, r, g, b, a)
                local alerts = EnsureAlerts(index)
                if alerts and alerts.actions[actIdx] then
                    alerts.actions[actIdx].color = { r, g, b, a }
                    DDingUI:UpdateBuffTrackerBar()
                end
            end,
        }

        -- Color target select (color action only)
        actionArgs["colorTarget"] = {
            type = "select",
            name = L["Target"] or "적용 대상",
            order = 3.5, width = 0.4,
            hidden = function()
                local buff = GetTrackedBuff(index)
                local a = buff and buff.settings and buff.settings.alerts and buff.settings.alerts.actions and buff.settings.alerts.actions[actIdx]
                return not a or a.type ~= "color"
            end,
            values = {
                self = L["Tracker (Self)"] or "해당 트래커",
                group = L["Group"] or "같은 그룹 트래커",
                bar = L["Resource Bar"] or "자원바",
                secondary_bar = L["Secondary Bar"] or "보조 자원바",
            },
            get = function()
                local buff = GetTrackedBuff(index)
                local a = buff and buff.settings and buff.settings.alerts and buff.settings.alerts.actions and buff.settings.alerts.actions[actIdx]
                return a and a.colorTarget or "self"
            end,
            set = function(_, val)
                local alerts = EnsureAlerts(index)
                if alerts and alerts.actions[actIdx] then
                    alerts.actions[actIdx].colorTarget = val
                    DDingUI:UpdateBuffTrackerBar()
                end
            end,
        }

        -- Sound file select (sound action only)
        actionArgs["soundFile"] = {
            type = "select",
            name = L["Sound File"] or "Sound File",
            order = 3, width = 0.5,
            hidden = function()
                local buff = GetTrackedBuff(index)
                local a = buff and buff.settings and buff.settings.alerts and buff.settings.alerts.actions and buff.settings.alerts.actions[actIdx]
                return not a or a.type ~= "sound"
            end,
            values = function()
                local values = {}
                local list = LSM:List("sound")
                for _, name in ipairs(list) do
                    values[name] = name
                end
                return values
            end,
            sorting = function()
                return LSM:List("sound")
            end,
            get = function()
                local buff = GetTrackedBuff(index)
                local a = buff and buff.settings and buff.settings.alerts and buff.settings.alerts.actions and buff.settings.alerts.actions[actIdx]
                return a and a.soundFile or "None"
            end,
            set = function(_, val)
                local alerts = EnsureAlerts(index)
                if alerts and alerts.actions[actIdx] then
                    alerts.actions[actIdx].soundFile = val
                    if val and val ~= "None" then
                        local soundPath = LSM:Fetch("sound", val)
                        if soundPath then PlaySoundFile(soundPath, "Master") end
                    end
                end
            end,
        }

        -- Sound channel (sound action only)
        actionArgs["soundChannel"] = {
            type = "select",
            name = L["Channel"] or "Channel",
            order = 4, width = 0.3,
            hidden = function()
                local buff = GetTrackedBuff(index)
                local a = buff and buff.settings and buff.settings.alerts and buff.settings.alerts.actions and buff.settings.alerts.actions[actIdx]
                return not a or a.type ~= "sound"
            end,
            values = {
                Master = L["Master"] or "Master",
                SFX = L["SFX"] or "SFX",
                Music = L["Music"] or "Music",
                Ambience = L["Ambience"] or "Ambience",
                Dialog = L["Dialog"] or "Dialog",
            },
            get = function()
                local buff = GetTrackedBuff(index)
                local a = buff and buff.settings and buff.settings.alerts and buff.settings.alerts.actions and buff.settings.alerts.actions[actIdx]
                return a and a.soundChannel or "Master"
            end,
            set = function(_, val)
                local alerts = EnsureAlerts(index)
                if alerts and alerts.actions[actIdx] then
                    alerts.actions[actIdx].soundChannel = val
                end
            end,
        }

        -- Sound mode (once/repeat) (sound action only)
        actionArgs["soundMode"] = {
            type = "select",
            name = L["Mode"] or "Mode",
            order = 5, width = 0.35,
            hidden = function()
                local buff = GetTrackedBuff(index)
                local a = buff and buff.settings and buff.settings.alerts and buff.settings.alerts.actions and buff.settings.alerts.actions[actIdx]
                return not a or a.type ~= "sound"
            end,
            values = {
                once = L["Once"] or "Once",
                ["repeat"] = L["Repeat"] or "Repeat",
            },
            get = function()
                local buff = GetTrackedBuff(index)
                local a = buff and buff.settings and buff.settings.alerts and buff.settings.alerts.actions and buff.settings.alerts.actions[actIdx]
                return a and a.soundMode or "once"
            end,
            set = function(_, val)
                local alerts = EnsureAlerts(index)
                if alerts and alerts.actions[actIdx] then
                    alerts.actions[actIdx].soundMode = val
                    RefreshOptions()
                end
            end,
        }

        -- Sound cooldown (repeat mode only)
        actionArgs["soundCooldown"] = {
            type = "range",
            name = (L["Interval"] or "Interval") .. " (s)",
            order = 6, width = 0.5,
            min = 1, max = 30, step = 1,
            hidden = function()
                local buff = GetTrackedBuff(index)
                local a = buff and buff.settings and buff.settings.alerts and buff.settings.alerts.actions and buff.settings.alerts.actions[actIdx]
                return not a or a.type ~= "sound" or a.soundMode ~= "repeat"
            end,
            get = function()
                local buff = GetTrackedBuff(index)
                local a = buff and buff.settings and buff.settings.alerts and buff.settings.alerts.actions and buff.settings.alerts.actions[actIdx]
                return a and a.soundCooldown or 3
            end,
            set = function(_, val)
                local alerts = EnsureAlerts(index)
                if alerts and alerts.actions[actIdx] then
                    alerts.actions[actIdx].soundCooldown = val
                end
            end,
        }

        -- Custom sound path (sound action only)
        actionArgs["soundCustomPath"] = {
            type = "input",
            name = L["Custom Path"] or "Custom Path",
            desc = (L["Custom sound file path (mp3/ogg/wav). Overrides dropdown when set."] or "Custom sound file path (mp3/ogg/wav). Overrides dropdown when set."),
            order = 7, width = 1.2,
            hidden = function()
                local buff = GetTrackedBuff(index)
                local a = buff and buff.settings and buff.settings.alerts and buff.settings.alerts.actions and buff.settings.alerts.actions[actIdx]
                return not a or a.type ~= "sound"
            end,
            get = function()
                local buff = GetTrackedBuff(index)
                local a = buff and buff.settings and buff.settings.alerts and buff.settings.alerts.actions and buff.settings.alerts.actions[actIdx]
                return a and a.soundCustomPath or ""
            end,
            set = function(_, val)
                local alerts = EnsureAlerts(index)
                if alerts and alerts.actions[actIdx] then
                    if val and val ~= "" then
                        local ext = val:lower():match("%.(%w+)$")
                        if ext ~= "mp3" and ext ~= "ogg" and ext ~= "wav" then
                            print(CDM_PREFIX .. "|cffff4444" .. (L["Invalid sound format. Use mp3, ogg, or wav."] or "Invalid sound format. Use mp3, ogg, or wav."))
                            return
                        end
                    end
                    alerts.actions[actIdx].soundCustomPath = val or ""
                    if val and val ~= "" then
                        local channel = alerts.actions[actIdx].soundChannel or "Master"
                        PlaySoundFile(val, channel)
                    end
                end
            end,
        }

        -- Remove action button
        local actIdxCapture = actIdx
        actionArgs["remove"] = {
            type = "execute",
            name = "|cffff4444" .. (L["Delete Action"] or "Delete") .. "|r",
            order = 99, width = "normal",
            func = function()
                local alerts = EnsureAlerts(index)
                if alerts and alerts.actions then
                    table.remove(alerts.actions, actIdxCapture)
                    DDingUI:UpdateBuffTrackerBar()
                    RefreshOptions()
                end
            end,
        }

        -- 동작 타입 이름 조회 (폴더블 제목용)
        local function getActionTypeName()
            local buff = GetTrackedBuff(index)
            local a = buff and buff.settings and buff.settings.alerts and buff.settings.alerts.actions and buff.settings.alerts.actions[actIdx]
            if a then
                return actionTypeDisplayNames[a.type] or a.type or "?"
            end
            return "?"
        end

        -- 폴더블 inline group으로 등록
        options["tracked" .. index .. "_alertAction" .. actIdx] = {
            type = "group",
            name = function()
                return (L["Action"] or "Action") .. " " .. actIdx .. "  |cff888888(" .. getActionTypeName() .. ")|r"
            end,
            order = actOrderBase,
            inline = true,
            hidden = hiddenIfActionNotExists,
            args = actionArgs,
        }
    end

    -- Add Action button
    options["tracked" .. index .. "_alertAddAction"] = {
        type = "execute",
        name = "+ " .. (L["Add Action"] or "Add Action"),
        order = orderBase + 8.90,
        width = 0.6,
        hidden = function()
            if hiddenIfAlertsOff() then return true end
            local buff = GetTrackedBuff(index)
            local actions = buff and buff.settings and buff.settings.alerts and buff.settings.alerts.actions or {}
            return #actions >= MAX_ALERT_ACTIONS
        end,
        func = function()
            local alerts = EnsureAlerts(index)
            if alerts then
                table.insert(alerts.actions, { type = "color", condition = "any", color = { 1, 0, 0, 1 } })
                DDingUI:UpdateBuffTrackerBar()
                RefreshOptions()
            end
        end,
    }

    -- Separator line (only show when buff exists AND is expanded)
    if not skipCollapsible then
        options["tracked" .. index .. "_spacer"] = {
            type = "description",
            name = " ",
            order = orderBase + 10,
            width = "full",
            hidden = hiddenIfCollapsed,
        }
    end

    return options
end

-- Create all tracked buff list options
local function CreateTrackedBuffListOptions(baseOrder)
    local options = {}
    local MAX_TRACKED_BUFFS = 20

    -- Header instead of inline group (no background)
    options["trackedBuffsHeader"] = {
        type = "header",
        name = function()
            local count = #GetTrackedBuffs()
            return (L["Tracked Buffs"] or "Tracked Buffs") .. " (" .. count .. ")"
        end,
        order = baseOrder,
    }

    -- Description
    options["trackedListDesc"] = {
        type = "description",
        name = "|cff888888" .. (L["Click header to expand settings, X to remove"] or "Click header to expand settings, X to remove") .. "|r",
        order = baseOrder + 0.1,
    }

    -- Empty message
    options["trackedListEmpty"] = {
        type = "description",
        name = "\n|cffaaaaaa" .. (L["No buffs being tracked. Select a buff from the catalog above."] or "No buffs being tracked. Select a buff from the catalog above.") .. "|r\n",
        order = baseOrder + 0.2,
        fontSize = "medium",
        hidden = function()
            return #GetTrackedBuffs() > 0
        end,
    }

    -- Create slots for tracked buffs (order: baseOrder + 1 ~ baseOrder + 401)
    for i = 1, MAX_TRACKED_BUFFS do
        local buffOpts = CreateTrackedBuffOptions(i, baseOrder + (i * 20))
        for k, v in pairs(buffOpts) do
            options[k] = v
        end
    end

    return options
end

-- 오라 아이콘 옵션 생성 (CDM 동적 슬롯 사용)
local function CreateAuraIconOptions(baseOrder)
    -- CDM 카탈로그 동적 슬롯 사용
    return CreateCDMCatalogSlotOptions(baseOrder)
end


-- [REFACTOR] Global settings extracted for WeakAuras-style panel (GUI.lua "Global Settings" page)
local function CreateGlobalBuffTrackerSettings()
    local options = {}

    options["header"] = {
        type = "header",
        name = L["Buff Tracker Bar Settings"] or "Buff Tracker Bar Settings",
        order = 1,
    }
    options["description"] = {
        type = "description",
        name = L["Track spell casts to display stacks as a resource bar. Configure trigger spells that generate stacks and consumer spells that spend stacks."] or "Track spell casts to display stacks as a resource bar. Configure trigger spells that generate stacks and consumer spells that spend stacks.",
        order = 1.5,
    }
    options["enabled"] = {
        type = "toggle",
        name = L["Enable Buff Tracker Bar"] or "Enable Buff Tracker Bar",
        desc = L["Show a bar that tracks a specific buff's stacks"] or "Show a bar that tracks a specific buff's stacks",
        width = "full",
        order = 2,
        get = function() return DDingUI.db.profile.buffTrackerBar.enabled end,
        set = function(_, val)
            DDingUI.db.profile.buffTrackerBar.enabled = val
            local cfg = GetSpecConfig()
            if cfg and not cfg.trackingMode then
                cfg.trackingMode = "cdm"
            end
            DDingUI:UpdateBuffTrackerBar()
        end,
    }
    options["previewMode"] = {
        type = "toggle",
        name = L["Preview Mode"] or "Preview Mode",
        desc = L["Show all tracked buffs for configuration (ignores hideWhenZero)"] or "Show all tracked buffs for configuration (ignores hideWhenZero)",
        width = "full",
        order = 2.5,
        get = function()
            return DDingUI.IsBuffTrackerPreviewEnabled and DDingUI:IsBuffTrackerPreviewEnabled() or false
        end,
        set = function(_, val)
            if val then
                DDingUI:EnableBuffTrackerPreview()
            else
                DDingUI:DisableBuffTrackerPreview()
            end
        end,
    }

    -- ========== GROWTH DIRECTION ==========
    options["growthDirectionHeader"] = {
        type = "description",
        name = "|cffffcc00" .. (L["Growth Direction"] or "Growth Direction") .. "|r",
        order = 3, width = "full", fontSize = "medium",
    }
    options["growthDirection"] = {
        type = "select",
        name = L["Growth Direction"] or "Growth Direction",
        desc = L["Direction in which multiple bars/rings stack"] or "Direction in which multiple bars/rings stack",
        order = 3.1, width = 0.8,
        values = {
            ["DOWN"] = L["Down"] or "Down",
            ["UP"] = L["Up"] or "Up",
            ["LEFT"] = L["Left"] or "Left",
            ["RIGHT"] = L["Right"] or "Right",
        },
        get = function() return DDingUI.db.profile.buffTrackerBar.growthDirection or "DOWN" end,
        set = function(_, val)
            DDingUI.db.profile.buffTrackerBar.growthDirection = val
            DDingUI:UpdateBuffTrackerBar()
        end,
    }
    options["growthSpacing"] = {
        type = "range",
        name = L["Growth Spacing"] or "Growth Spacing",
        desc = L["Spacing between stacked bars/rings"] or "Spacing between stacked bars/rings",
        order = 3.2, width = 0.8,
        min = 0, max = 50, step = 1,
        get = function() return DDingUI.db.profile.buffTrackerBar.growthSpacing or 20 end,
        set = function(_, val)
            DDingUI.db.profile.buffTrackerBar.growthSpacing = val
            DDingUI:UpdateBuffTrackerBar()
        end,
    }

    -- ========== POSITION & ANCHOR ==========
    options["positionHeader"] = {
        type = "description",
        name = "|cffffcc00" .. (L["Position & Anchor"] or "Position & Anchor") .. "|r",
        order = 3.3, width = "full", fontSize = "medium",
    }
    options["attachTo"] = {
        type = "select",
        name = L["Attach To"] or "Attach To",
        desc = L["Which frame to attach this bar to"] or "Which frame to attach this bar to",
        order = 3.31, width = "double",
        values = function()
            local opts = {}
            opts["UIParent"] = L["Screen (UIParent)"] or "Screen (UIParent)"
            if DDingUI.db.profile.unitFrames and DDingUI.db.profile.unitFrames.enabled then
                opts["DDingUI_Player"] = L["Player Frame (Custom)"] or "Player Frame (Custom)"
            end
            opts["PlayerFrame"] = L["Default Player Frame"] or "Default Player Frame"
            local viewerOpts = GetViewerOptions()
            for k, v in pairs(viewerOpts) do
                opts[k] = v
            end
            local current = DDingUI.db.profile.buffTrackerBar.attachTo
            if current and not opts[current] then
                opts[current] = current .. " (Custom)"
            end
            return opts
        end,
        get = function() return DDingUI.db.profile.buffTrackerBar.attachTo end,
        set = function(_, val)
            DDingUI.db.profile.buffTrackerBar.attachTo = val
            DDingUI:UpdateBuffTrackerBar()
            if DDingUI.Movers and DDingUI.Movers.LoadMoverPosition then
                DDingUI.Movers:LoadMoverPosition("DDingUI_BuffTrackerBar")
            end
            MarkSpecDirty()
        end,
    }
    options["pickFrameGlobal"] = {
        type = "execute",
        name = L["Pick Frame"] or "Pick Frame",
        desc = L["Click to select a frame from the UI"] or "Click to select a frame from the UI",
        order = 3.315, width = "half",
        func = function()
            DDingUI:StartFramePicker(function(frameName)
                if frameName then
                    DDingUI.db.profile.buffTrackerBar.attachTo = frameName
                    DDingUI:UpdateBuffTrackerBar()
                end
            end)
        end,
    }
    options["anchorPoint"] = {
        type = "select",
        name = L["Anchor Point"] or "Anchor Point",
        desc = L["Which point on the anchor frame to attach to"] or "Which point on the anchor frame to attach to",
        order = 3.32, width = "normal",
        values = {
            TOPLEFT = L["Top Left"] or "Top Left", TOP = L["Top"] or "Top", TOPRIGHT = L["Top Right"] or "Top Right",
            LEFT = L["Left"] or "Left", CENTER = L["Center"] or "Center", RIGHT = L["Right"] or "Right",
            BOTTOMLEFT = L["Bottom Left"] or "Bottom Left", BOTTOM = L["Bottom"] or "Bottom", BOTTOMRIGHT = L["Bottom Right"] or "Bottom Right",
        },
        get = function() return DDingUI.db.profile.buffTrackerBar.anchorPoint or "TOP" end,
        set = function(_, val)
            DDingUI.db.profile.buffTrackerBar.anchorPoint = val
            DDingUI:UpdateBuffTrackerBar()
            if DDingUI.Movers and DDingUI.Movers.LoadMoverPosition then
                DDingUI.Movers:LoadMoverPosition("DDingUI_BuffTrackerBar")
            end
            MarkSpecDirty()
        end,
    }
    options["selfPoint"] = {
        type = "select",
        name = L["Self Point"] or "Self Point",
        desc = L["Which point of the bar itself is used for anchoring"] or "Which point of the bar itself is used for anchoring",
        order = 3.325, width = "normal",
        values = {
            TOPLEFT = L["Top Left"] or "Top Left", TOP = L["Top"] or "Top", TOPRIGHT = L["Top Right"] or "Top Right",
            LEFT = L["Left"] or "Left", CENTER = L["Center"] or "Center", RIGHT = L["Right"] or "Right",
            BOTTOMLEFT = L["Bottom Left"] or "Bottom Left", BOTTOM = L["Bottom"] or "Bottom", BOTTOMRIGHT = L["Bottom Right"] or "Bottom Right",
        },
        get = function() return DDingUI.db.profile.buffTrackerBar.selfPoint or "TOP" end,
        set = function(_, val)
            DDingUI.db.profile.buffTrackerBar.selfPoint = val
            DDingUI:UpdateBuffTrackerBar()
            if DDingUI.Movers and DDingUI.Movers.LoadMoverPosition then
                DDingUI.Movers:LoadMoverPosition("DDingUI_BuffTrackerBar")
            end
            MarkSpecDirty()
        end,
    }
    options["offsetX"] = {
        type = "range",
        name = L["X Offset"] or "X Offset",
        desc = L["Horizontal offset from anchor point"] or "Horizontal offset from anchor point",
        order = 3.33, width = "normal",
        min = -500, max = 500, step = 1,
        get = function() return DDingUI.db.profile.buffTrackerBar.offsetX or 0 end,
        set = function(_, val)
            DDingUI.db.profile.buffTrackerBar.offsetX = val
            DDingUI:UpdateBuffTrackerBar()
            if DDingUI.Movers and DDingUI.Movers.LoadMoverPosition then
                DDingUI.Movers:LoadMoverPosition("DDingUI_BuffTrackerBar")
            end
            MarkSpecDirty()
        end,
    }
    options["offsetY"] = {
        type = "range",
        name = L["Y Offset"] or "Y Offset",
        desc = L["Vertical offset from anchor point"] or "Vertical offset from anchor point",
        order = 3.34, width = "normal",
        min = -500, max = 500, step = 1,
        get = function() return DDingUI.db.profile.buffTrackerBar.offsetY or 18 end,
        set = function(_, val)
            DDingUI.db.profile.buffTrackerBar.offsetY = val
            DDingUI:UpdateBuffTrackerBar()
            if DDingUI.Movers and DDingUI.Movers.LoadMoverPosition then
                DDingUI.Movers:LoadMoverPosition("DDingUI_BuffTrackerBar")
            end
            MarkSpecDirty()
        end,
    }
    options["frameStrata"] = {
        type = "select",
        name = L["Frame Strata"] or "Frame Strata",
        desc = L["Controls the drawing layer of this bar. Higher strata appear on top of lower ones."] or "Controls the drawing layer of this bar.",
        order = 3.5, width = "normal",
        values = {
            BACKGROUND = "BACKGROUND", LOW = "LOW", MEDIUM = "MEDIUM", HIGH = "HIGH", DIALOG = "DIALOG",
        },
        get = function() return DDingUI.db.profile.buffTrackerBar.frameStrata or "MEDIUM" end,
        set = function(_, val)
            DDingUI.db.profile.buffTrackerBar.frameStrata = val
            DDingUI:UpdateBuffTrackerBar()
        end,
    }

    return options
end

local function CreateBuffTrackerOptions(orderNum)

    local options = {
        type = "group",
        name = L["Buff Tracker"] or "Buff Tracker",
        order = orderNum or 9,
        -- [REFACTOR] customRenderer: single node in main tree,
        -- content panel renders WeakAuras-style split-view directly
        customRenderer = "buffTracker",
        args = {}
    }

    -- Add spec profile options
    if DDingUI.SpecProfiles and DDingUI.SpecProfiles.AddSpecProfileOptions then
        DDingUI.SpecProfiles:AddSpecProfileOptions(
            options.args,
            "buffTrackerBar",
            L["Buff Tracker"] or "Buff Tracker",
            0,
            function() DDingUI:UpdateBuffTrackerBar() end
        )
    end

    return options
end

ns.CreateBuffTrackerOptions = CreateBuffTrackerOptions

-- [REFACTOR] Export internal functions for WeakAuras-style custom renderer (GUI.lua)
ns.CreateTrackedBuffOptions = CreateTrackedBuffOptions
ns.CreateTrackedBuffListOptions = CreateTrackedBuffListOptions
ns.CreateAuraIconOptions = CreateAuraIconOptions
ns.CreateGlobalBuffTrackerSettings = CreateGlobalBuffTrackerSettings
