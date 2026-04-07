--[[
    DDingUI_PersonalBar
    개인 자원바 (PersonalResourceDisplayFrame) 크기/텍스쳐 조절
    바: 텍스쳐, 너비, 높이 | 버블: 크기, 간격, Y 오프셋
]]

local addonName, ns = ...

------------------------------------------------------------------------
-- 상수
------------------------------------------------------------------------
local FLAT = "Interface\\Buttons\\WHITE8x8"
local FONT = "Fonts\\2002.TTF"
local TITLE_COLOR = { 1, 0.64, 0 }
local CHAT_PREFIX = "|cffffffffDDing|r|cffffa300UI|r |cff88cc44PersonalBar|r: "
local DEBUG = true  -- 디버그 모드

------------------------------------------------------------------------
-- 기본 설정값
------------------------------------------------------------------------
local DEFAULTS = {
    barTexture = "",
    barWidth   = 0,
    barHeight  = 0,
    bubbleScale   = 1.0,
    bubbleSpacing = 0,
    bubbleOffsetY = 0,
    minimap = { hide = false },
}

------------------------------------------------------------------------
-- 로컬 참조
------------------------------------------------------------------------
local db
local configFrame
local playerNameplate = nil -- NAME_PLATE_UNIT_ADDED 에서 캡쳐
local originalBubblePoints = {}

------------------------------------------------------------------------
-- 유틸
------------------------------------------------------------------------
local function MergeDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if target[k] == nil then
            if type(v) == "table" then
                target[k] = {}
                MergeDefaults(target[k], v)
            else
                target[k] = v
            end
        elseif type(v) == "table" and type(target[k]) == "table" then
            MergeDefaults(target[k], v)
        end
    end
end

local function DebugPrint(...)
    if DEBUG then print(CHAT_PREFIX .. "|cff66aaff[DEBUG]|r", ...) end
end

------------------------------------------------------------------------
-- 프레임 구조 덤프 (디버그용)
------------------------------------------------------------------------
local function DumpFrame(frame, prefix, depth)
    if not frame or depth > 3 then return end
    prefix = prefix or ""
    local name = frame.GetName and frame:GetName() or "(anonymous)"
    local objType = frame.GetObjectType and frame:GetObjectType() or "?"
    local w, h = 0, 0
    pcall(function() w, h = frame:GetSize() end)
    DebugPrint(prefix .. name .. " [" .. objType .. "] " .. math.floor(w) .. "x" .. math.floor(h))

    if frame.GetChildren then
        local children = { frame:GetChildren() }
        for i, child in ipairs(children) do
            DumpFrame(child, prefix .. "  ", depth + 1)
        end
    end
end

------------------------------------------------------------------------
-- 바 설정 적용
------------------------------------------------------------------------
local function ApplyBarSettings()
    if InCombatLockdown() then return end

    -- 방법 1: C_NamePlate.GetNamePlateForUnit("player")
    local np = C_NamePlate.GetNamePlateForUnit("player")
    if not np then
        -- 방법 2: 저장된 참조 사용
        np = playerNameplate
    end

    -- HealthBarsContainer
    local healthContainer
    if np then
        -- UnitFrame 경로 탐색
        local uf = np.UnitFrame
        if uf then
            healthContainer = uf.HealthBarsContainer
            if not healthContainer then
                -- 자식 프레임에서 찾기
                for _, child in pairs({ uf:GetChildren() }) do
                    local cname = child.GetName and child:GetName() or ""
                    if cname:find("HealthBarsContainer") or cname:find("Health") then
                        healthContainer = child
                        break
                    end
                end
            end
        end
    end

    -- Fallback: PersonalResourceDisplayFrame 글로벌
    if not healthContainer then
        local prd = _G.PersonalResourceDisplayFrame
        if prd then
            healthContainer = prd.HealthBarsContainer
        end
    end

    if healthContainer then
        DebugPrint("HealthContainer 찾음: " .. tostring(healthContainer:GetName() or healthContainer))
        if db.barWidth > 0 then healthContainer:SetWidth(db.barWidth) end
        if db.barHeight > 0 then healthContainer:SetHeight(db.barHeight) end

        local healthBar = healthContainer.healthBar
        if healthBar and db.barTexture ~= "" then
            if healthBar.SetStatusBarTexture then
                healthBar:SetStatusBarTexture(db.barTexture)
            end
        end
    else
        DebugPrint("HealthContainer 못 찾음!")
    end

    -- PowerBar: NamePlateDriverFrame 경로
    local powerBar
    if NamePlateDriverFrame then
        -- 방법 1: 메서드
        if NamePlateDriverFrame.GetClassNameplateManaBar then
            powerBar = NamePlateDriverFrame:GetClassNameplateManaBar()
        end
        -- 방법 2: 직접 속성
        if not powerBar then
            powerBar = NamePlateDriverFrame.classNamePlatePowerBar
        end
    end

    -- Fallback: PersonalResourceDisplayFrame.PowerBar
    if not powerBar then
        local prd = _G.PersonalResourceDisplayFrame
        if prd then powerBar = prd.PowerBar end
    end

    if powerBar then
        DebugPrint("PowerBar 찾음: " .. tostring(powerBar:GetName() or powerBar))
        if db.barWidth > 0 then powerBar:SetWidth(db.barWidth) end
        if db.barHeight > 0 then powerBar:SetHeight(db.barHeight) end
        if db.barTexture ~= "" and powerBar.SetStatusBarTexture then
            powerBar:SetStatusBarTexture(db.barTexture)
        end
    else
        DebugPrint("PowerBar 못 찾음!")
    end
end

------------------------------------------------------------------------
-- 버블 설정 적용
------------------------------------------------------------------------
local function ApplyBubbleSettings()
    if InCombatLockdown() then return end

    local mechanicFrame

    -- 방법 1: NamePlateDriverFrame 메서드
    if NamePlateDriverFrame then
        if NamePlateDriverFrame.GetClassNameplateBar then
            mechanicFrame = NamePlateDriverFrame:GetClassNameplateBar()
        end
        if not mechanicFrame then
            mechanicFrame = NamePlateDriverFrame.classNamePlateMechanicFrame
        end
    end

    if not mechanicFrame then
        DebugPrint("MechanicFrame (버블) 못 찾음!")

        -- 방법 2: PersonalResourceDisplayFrame 하위에서 클래스 바 찾기
        local prd = _G.PersonalResourceDisplayFrame
        if prd then
            for _, child in pairs({ prd:GetChildren() }) do
                local cname = child.GetName and child:GetName() or ""
                if cname:find("Class") then
                    mechanicFrame = child
                    DebugPrint("Fallback 버블 프레임: " .. cname)
                    break
                end
            end
        end

        -- 방법 3: 글로벌 이름으로 검색
        if not mechanicFrame then
            -- 일반적인 클래스 바 글로벌 이름들
            local globals = {
                "ClassNameplateBarComboPointFrame",
                "ClassNameplateBarRogueFrame",
                "ClassNameplateBarDruidFrame",
                "ClassNameplateBarPaladinFrame",
                "ClassNameplateBarMageFrame",
                "ClassNameplateBarWarlockFrame",
                "ClassNameplateBarMonkFrame",
                "ClassNameplateBarDeathKnightFrame",
                "ClassNameplateBarDemonHunterFrame",
                "ClassNameplateBarEvokerFrame",
                "ClassNameplateBarWindwalkerMonkFrame",
                "ClassNameplateBarFeralDruidFrame",
            }
            for _, gname in ipairs(globals) do
                if _G[gname] then
                    mechanicFrame = _G[gname]
                    DebugPrint("글로벌 버블 프레임 발견: " .. gname)
                    break
                end
            end
        end

        if not mechanicFrame then return end
    else
        DebugPrint("MechanicFrame 찾음: " .. tostring(mechanicFrame:GetName() or mechanicFrame))
    end

    -- 스케일
    pcall(function()
        if db.bubbleScale ~= 1.0 then
            mechanicFrame:SetScale(db.bubbleScale)
        else
            mechanicFrame:SetScale(1.0)
        end
    end)

    -- 개별 버블 간격/Y오프셋
    local children = {}
    pcall(function() children = { mechanicFrame:GetChildren() } end)

    for i, child in ipairs(children) do
        if child and child:GetNumPoints() and child:GetNumPoints() > 0 then
            local key = tostring(child)
            if not originalBubblePoints[key] then
                local ok, point, relativeTo, relativePoint, xOfs, yOfs = pcall(child.GetPoint, child, 1)
                if ok and point then
                    originalBubblePoints[key] = { point, relativeTo, relativePoint, xOfs or 0, yOfs or 0 }
                end
            end

            local orig = originalBubblePoints[key]
            if orig then
                local extraX = (i > 1) and db.bubbleSpacing or 0
                local extraY = db.bubbleOffsetY
                if extraX ~= 0 or extraY ~= 0 then
                    pcall(function()
                        child:ClearAllPoints()
                        child:SetPoint(orig[1], orig[2], orig[3],
                            orig[4] + extraX, orig[5] + extraY)
                    end)
                end
            end
        end
    end
end

------------------------------------------------------------------------
-- 전체 적용
------------------------------------------------------------------------
local function ApplyAll()
    if InCombatLockdown() then return end
    ApplyBarSettings()
    ApplyBubbleSettings()
end

------------------------------------------------------------------------
-- GUI 헬퍼
------------------------------------------------------------------------
local function CreateSlider(parent, label, minVal, maxVal, step, dbKey, x, y)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(280, 52)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

    local text = container:CreateFontString(nil, "OVERLAY")
    text:SetFont(FONT, 12, "")
    text:SetPoint("TOPLEFT", 0, 0)
    text:SetTextColor(0.85, 0.85, 0.85)
    text:SetText(label)

    local valueText = container:CreateFontString(nil, "OVERLAY")
    valueText:SetFont(FONT, 12, "")
    valueText:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
    valueText:SetTextColor(TITLE_COLOR[1], TITLE_COLOR[2], TITLE_COLOR[3])

    local slider = CreateFrame("Slider", nil, container, "BackdropTemplate")
    slider:SetSize(260, 16)
    slider:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -6)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(db[dbKey] or minVal)

    slider:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    slider:SetBackdropColor(0.06, 0.06, 0.06, 0.9)
    slider:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.7)

    local thumb = slider:CreateTexture(nil, "ARTWORK")
    thumb:SetSize(12, 16)
    thumb:SetTexture(FLAT)
    thumb:SetVertexColor(TITLE_COLOR[1], TITLE_COLOR[2], TITLE_COLOR[3], 0.9)
    slider:SetThumbTexture(thumb)

    local function UpdateValue(val)
        if step < 1 then
            valueText:SetText(string.format("%.1f", val))
        else
            valueText:SetText(tostring(math.floor(val)))
        end
    end
    UpdateValue(db[dbKey] or minVal)

    slider:SetScript("OnValueChanged", function(self, val)
        db[dbKey] = val
        UpdateValue(val)
        ApplyAll()
    end)

    local minLabel = container:CreateFontString(nil, "OVERLAY")
    minLabel:SetFont(FONT, 10, "")
    minLabel:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -2)
    minLabel:SetTextColor(0.5, 0.5, 0.5)
    minLabel:SetText(tostring(minVal))

    local maxLabel = container:CreateFontString(nil, "OVERLAY")
    maxLabel:SetFont(FONT, 10, "")
    maxLabel:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", 0, -2)
    maxLabel:SetTextColor(0.5, 0.5, 0.5)
    maxLabel:SetText(tostring(maxVal))

    container.slider = slider
    return container
end

local function CreateEditBox(parent, label, dbKey, x, y)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(280, 38)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

    local text = container:CreateFontString(nil, "OVERLAY")
    text:SetFont(FONT, 12, "")
    text:SetPoint("TOPLEFT", 0, 0)
    text:SetTextColor(0.85, 0.85, 0.85)
    text:SetText(label)

    local editBox = CreateFrame("EditBox", nil, container, "BackdropTemplate")
    editBox:SetSize(260, 22)
    editBox:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -4)
    editBox:SetBackdrop({
        bgFile = FLAT, edgeFile = FLAT, edgeSize = 1,
        insets = { left = 4, right = 4, top = 2, bottom = 2 },
    })
    editBox:SetBackdropColor(0.06, 0.06, 0.06, 0.9)
    editBox:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.7)
    editBox:SetFont(FONT, 11, "")
    editBox:SetTextColor(0.85, 0.85, 0.85)
    editBox:SetAutoFocus(false)
    editBox:SetMaxLetters(256)
    editBox:SetText(db[dbKey] or "")

    editBox:SetScript("OnEnterPressed", function(self)
        db[dbKey] = self:GetText()
        self:ClearFocus()
        ApplyAll()
    end)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    editBox:SetScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(TITLE_COLOR[1], TITLE_COLOR[2], TITLE_COLOR[3], 0.8)
    end)
    editBox:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.7)
    end)

    container.editBox = editBox
    return container
end

------------------------------------------------------------------------
-- GUI 메인 패널
------------------------------------------------------------------------
local function CreateConfigFrame()
    if configFrame then
        configFrame:Show()
        return
    end

    local f = CreateFrame("Frame", "DDingUI_PersonalBarConfig", UIParent, "BackdropTemplate")
    f:SetSize(340, 520)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(100)
    f:SetMovable(true)
    f:EnableMouse(true)

    f:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    f:SetBackdropColor(0.08, 0.08, 0.08, 0.97)
    f:SetBackdropBorderColor(0.18, 0.18, 0.18, 0.7)

    local titleBar = f:CreateTexture(nil, "ARTWORK", nil, -6)
    titleBar:SetTexture(FLAT)
    titleBar:SetPoint("TOPLEFT", 1, -1)
    titleBar:SetPoint("TOPRIGHT", -1, -1)
    titleBar:SetHeight(28)
    titleBar:SetVertexColor(0.14, 0.14, 0.14, 1)

    local accent = f:CreateTexture(nil, "OVERLAY", nil, 7)
    accent:SetTexture(FLAT)
    accent:SetHeight(2)
    accent:SetPoint("TOPLEFT", 0, 0)
    accent:SetPoint("TOPRIGHT", 0, 0)
    accent:SetVertexColor(TITLE_COLOR[1], TITLE_COLOR[2], TITLE_COLOR[3], 1)

    local titleText = f:CreateFontString(nil, "OVERLAY")
    titleText:SetFont(FONT, 14, "")
    titleText:SetPoint("CENTER", titleBar, "CENTER")
    titleText:SetTextColor(0.9, 0.9, 0.9)
    titleText:SetText("|cffffffffDDing|r|cffffa300UI|r |cff88cc44PersonalBar|r")

    local dragFrame = CreateFrame("Frame", nil, f)
    dragFrame:SetPoint("TOPLEFT", titleBar)
    dragFrame:SetPoint("BOTTOMRIGHT", titleBar)
    dragFrame:EnableMouse(true)
    dragFrame:RegisterForDrag("LeftButton")
    dragFrame:SetScript("OnDragStart", function() f:StartMoving() end)
    dragFrame:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("TOPRIGHT", -4, -5)
    local closeLabel = closeBtn:CreateFontString(nil, "OVERLAY")
    closeLabel:SetFont(FONT, 14, "OUTLINE")
    closeLabel:SetPoint("CENTER")
    closeLabel:SetText("✕")
    closeLabel:SetTextColor(0.55, 0.55, 0.55)
    closeBtn:SetScript("OnClick", function() f:Hide() end)
    closeBtn:SetScript("OnEnter", function() closeLabel:SetTextColor(1, 0.3, 0.3) end)
    closeBtn:SetScript("OnLeave", function() closeLabel:SetTextColor(0.55, 0.55, 0.55) end)

    local sep = f:CreateTexture(nil, "ARTWORK", nil, -5)
    sep:SetTexture(FLAT)
    sep:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT")
    sep:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT")
    sep:SetHeight(1)
    sep:SetVertexColor(0.22, 0.22, 0.22, 0.8)

    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -30)
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)

    local pad = 16
    local yOff = -pad

    -- 바 설정
    local barHeader = content:CreateFontString(nil, "OVERLAY")
    barHeader:SetFont(FONT, 13, "")
    barHeader:SetPoint("TOPLEFT", content, "TOPLEFT", pad, yOff)
    barHeader:SetTextColor(TITLE_COLOR[1], TITLE_COLOR[2], TITLE_COLOR[3])
    barHeader:SetText("— 바 설정 (체력+파워) —")
    yOff = yOff - 22

    CreateEditBox(content, "텍스쳐 경로 (빈값 = 기본)", "barTexture", pad, yOff)
    yOff = yOff - 48

    CreateSlider(content, "너비 (0 = 기본)", 0, 300, 1, "barWidth", pad, yOff)
    yOff = yOff - 60

    CreateSlider(content, "높이 (0 = 기본)", 0, 30, 1, "barHeight", pad, yOff)
    yOff = yOff - 68

    -- 버블 설정
    local bubbleHeader = content:CreateFontString(nil, "OVERLAY")
    bubbleHeader:SetFont(FONT, 13, "")
    bubbleHeader:SetPoint("TOPLEFT", content, "TOPLEFT", pad, yOff)
    bubbleHeader:SetTextColor(TITLE_COLOR[1], TITLE_COLOR[2], TITLE_COLOR[3])
    bubbleHeader:SetText("— 버블 설정 (콤보/에센스 등) —")
    yOff = yOff - 22

    CreateSlider(content, "크기 배율", 0.3, 3.0, 0.1, "bubbleScale", pad, yOff)
    yOff = yOff - 60

    CreateSlider(content, "간격", -20, 20, 1, "bubbleSpacing", pad, yOff)
    yOff = yOff - 60

    CreateSlider(content, "Y 오프셋", -30, 30, 1, "bubbleOffsetY", pad, yOff)
    yOff = yOff - 68

    -- 버튼
    local applyBtn = CreateFrame("Button", nil, content, "BackdropTemplate")
    applyBtn:SetSize(130, 26)
    applyBtn:SetPoint("TOPLEFT", content, "TOPLEFT", pad, yOff)
    applyBtn:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    applyBtn:SetBackdropColor(0.15, 0.15, 0.15, 0.95)
    applyBtn:SetBackdropBorderColor(TITLE_COLOR[1], TITLE_COLOR[2], TITLE_COLOR[3], 0.6)
    local applyText = applyBtn:CreateFontString(nil, "OVERLAY")
    applyText:SetFont(FONT, 12, "")
    applyText:SetPoint("CENTER")
    applyText:SetText("적용")
    applyText:SetTextColor(0.85, 0.85, 0.85)
    applyBtn:SetScript("OnClick", function()
        ApplyAll()
        print(CHAT_PREFIX .. "설정이 적용되었습니다.")
    end)
    applyBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(TITLE_COLOR[1], TITLE_COLOR[2], TITLE_COLOR[3], 1)
        applyText:SetTextColor(1, 1, 1)
    end)
    applyBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(TITLE_COLOR[1], TITLE_COLOR[2], TITLE_COLOR[3], 0.6)
        applyText:SetTextColor(0.85, 0.85, 0.85)
    end)

    local resetBtn = CreateFrame("Button", nil, content, "BackdropTemplate")
    resetBtn:SetSize(130, 26)
    resetBtn:SetPoint("LEFT", applyBtn, "RIGHT", 10, 0)
    resetBtn:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    resetBtn:SetBackdropColor(0.15, 0.15, 0.15, 0.95)
    resetBtn:SetBackdropBorderColor(0.4, 0.15, 0.15, 0.6)
    local resetText = resetBtn:CreateFontString(nil, "OVERLAY")
    resetText:SetFont(FONT, 12, "")
    resetText:SetPoint("CENTER")
    resetText:SetText("초기화")
    resetText:SetTextColor(0.85, 0.85, 0.85)
    resetBtn:SetScript("OnClick", function()
        DDingUI_PersonalBarDB = {}
        MergeDefaults(DDingUI_PersonalBarDB, DEFAULTS)
        db = DDingUI_PersonalBarDB
        wipe(originalBubblePoints)
        ApplyAll()
        f:Hide()
        configFrame = nil
        CreateConfigFrame()
        print(CHAT_PREFIX .. "설정이 초기화되었습니다.")
    end)
    resetBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.85, 0.2, 0.2, 0.8)
        resetText:SetTextColor(1, 1, 1)
    end)
    resetBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.4, 0.15, 0.15, 0.6)
        resetText:SetTextColor(0.85, 0.85, 0.85)
    end)

    tinsert(UISpecialFrames, "DDingUI_PersonalBarConfig")
    configFrame = f
end

------------------------------------------------------------------------
-- 미니맵 버튼
------------------------------------------------------------------------
local function CreateMinimapButton()
    local LDB = LibStub("LibDataBroker-1.1")
    local LDBIcon = LibStub("LibDBIcon-1.0")

    local launcher = LDB:NewDataObject("DDingUI_PersonalBar", {
        type = "launcher",
        label = "DDingUI PersonalBar",
        icon = "Interface\\AddOns\\DDingUI_PersonalBar\\logo",
        OnClick = function(_, button)
            if button == "LeftButton" then
                if configFrame and configFrame:IsShown() then
                    configFrame:Hide()
                else
                    CreateConfigFrame()
                end
            elseif button == "RightButton" then
                ApplyAll()
                print(CHAT_PREFIX .. "설정이 재적용되었습니다.")
            end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine("|cffffffffDDing|r|cffffa300UI|r |cff88cc44PersonalBar|r")
            tt:AddLine(" ")
            tt:AddLine("|cFFFFFF00좌클릭|r 설정 열기", 0.8, 0.8, 0.8)
            tt:AddLine("|cFFFFFF00우클릭|r 설정 재적용", 0.8, 0.8, 0.8)
        end,
    })

    LDBIcon:Register("DDingUI_PersonalBar", launcher, db.minimap)
end

------------------------------------------------------------------------
-- 이벤트 처리
------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        if not DDingUI_PersonalBarDB then DDingUI_PersonalBarDB = {} end
        MergeDefaults(DDingUI_PersonalBarDB, DEFAULTS)
        db = DDingUI_PersonalBarDB
        CreateMinimapButton()

    elseif event == "PLAYER_LOGIN" then
        C_Timer.After(2, function()
            ApplyAll()
            DebugPrint("PLAYER_LOGIN 적용 완료")
        end)
        print(CHAT_PREFIX .. "v1.1 로드됨. |cFFFFFF00/dpb|r 설정 | |cFFFFFF00/dpb dump|r 프레임 구조 확인")

    elseif event == "NAME_PLATE_UNIT_ADDED" then
        if arg1 and UnitIsUnit(arg1, "player") then
            playerNameplate = C_NamePlate.GetNamePlateForUnit(arg1)
            DebugPrint("플레이어 네임플레이트 감지: " .. tostring(playerNameplate))

            -- 약간의 딜레이 (프레임이 완전히 setup되기를 기다림)
            C_Timer.After(0.3, ApplyAll)
        end

    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        if arg1 and UnitIsUnit(arg1, "player") then
            playerNameplate = nil
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        if db then C_Timer.After(0.2, ApplyAll) end
    end
end)

------------------------------------------------------------------------
-- 슬래시 커맨드
------------------------------------------------------------------------
SLASH_DDINGPERSONALBAR1 = "/dpb"
SLASH_DDINGPERSONALBAR2 = "/personalbar"

SlashCmdList["DDINGPERSONALBAR"] = function(msg)
    msg = strtrim(msg or ""):lower()

    if msg == "" or msg == "config" or msg == "설정" then
        CreateConfigFrame()
        return
    end

    if msg == "dump" then
        print(CHAT_PREFIX .. "|cFFFF8800== 프레임 구조 덤프 ==|r")

        -- 1) C_NamePlate
        local np = C_NamePlate.GetNamePlateForUnit("player")
        print("  C_NamePlate.GetNamePlateForUnit('player'): " .. tostring(np))
        if np then
            DumpFrame(np, "    ", 0)
        end

        -- 2) PersonalResourceDisplayFrame
        local prd = _G.PersonalResourceDisplayFrame
        print("  PersonalResourceDisplayFrame: " .. tostring(prd))
        if prd then
            DumpFrame(prd, "    ", 0)
        end

        -- 3) NamePlateDriverFrame
        local npd = _G.NamePlateDriverFrame
        print("  NamePlateDriverFrame: " .. tostring(npd))
        if npd then
            print("    .classNamePlateMechanicFrame: " .. tostring(npd.classNamePlateMechanicFrame))
            print("    .classNamePlatePowerBar: " .. tostring(npd.classNamePlatePowerBar))
            print("    .classNamePlateAlternatePowerBar: " .. tostring(npd.classNamePlateAlternatePowerBar))
            if npd.GetClassNameplateBar then
                print("    :GetClassNameplateBar(): " .. tostring(npd:GetClassNameplateBar()))
            end
            if npd.GetClassNameplateManaBar then
                print("    :GetClassNameplateManaBar(): " .. tostring(npd:GetClassNameplateManaBar()))
            end
        end

        -- 4) 글로벌 클래스 네임플레이트 바 검색
        print("  == 글로벌 클래스 바 검색 ==")
        local classBarNames = {
            "ClassNameplateBarComboPointFrame",
            "ClassNameplateBarRogueFrame",
            "ClassNameplateBarDruidFrame",
            "ClassNameplateBarPaladinFrame",
            "ClassNameplateBarMageFrame",
            "ClassNameplateBarWarlockFrame",
            "ClassNameplateBarMonkFrame",
            "ClassNameplateBarDeathKnightFrame",
            "ClassNameplateBarDemonHunterFrame",
            "ClassNameplateBarEvokerFrame",
            "ClassNameplateBarWindwalkerMonkFrame",
            "ClassNameplateBarFeralDruidFrame",
            "ClassNameplateManaBarFrame",
        }
        for _, gname in ipairs(classBarNames) do
            if _G[gname] then
                print("    ✓ " .. gname .. " = " .. tostring(_G[gname]))
            end
        end

        -- 5) 저장된 참조
        print("  playerNameplate(저장): " .. tostring(playerNameplate))

        return
    end

    if msg == "debug" then
        DEBUG = not DEBUG
        print(CHAT_PREFIX .. "디버그 모드: " .. (DEBUG and "ON" or "OFF"))
        return
    end

    if msg == "help" then
        print(CHAT_PREFIX .. "v1.1")
        print("  /dpb — 설정 GUI 열기")
        print("  /dpb dump — 프레임 구조 덤프")
        print("  /dpb debug — 디버그 모드 토글")
        print("  /dpb apply — 수동 적용")
        print("  /dpb reset — 초기화")
        print("  /dpb status — 현재 설정")
        return
    end

    if msg == "status" then
        print(CHAT_PREFIX .. "현재 설정:")
        print("  barTexture: " .. (db.barTexture ~= "" and db.barTexture or "(기본)"))
        print("  barWidth: " .. (db.barWidth > 0 and db.barWidth or "(기본)"))
        print("  barHeight: " .. (db.barHeight > 0 and db.barHeight or "(기본)"))
        print("  bubbleScale: " .. db.bubbleScale)
        print("  bubbleSpacing: " .. db.bubbleSpacing)
        print("  bubbleOffsetY: " .. db.bubbleOffsetY)
        return
    end

    if msg == "reset" then
        DDingUI_PersonalBarDB = {}
        MergeDefaults(DDingUI_PersonalBarDB, DEFAULTS)
        db = DDingUI_PersonalBarDB
        wipe(originalBubblePoints)
        ApplyAll()
        if configFrame then configFrame:Hide(); configFrame = nil end
        print(CHAT_PREFIX .. "설정이 초기화되었습니다.")
        return
    end

    if msg == "apply" then
        ApplyAll()
        print(CHAT_PREFIX .. "설정이 적용되었습니다.")
        return
    end

    print(CHAT_PREFIX .. "알 수 없는 명령어. /dpb help")
end
