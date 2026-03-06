----------------------------------------------------------------------
-- DDingUI Nameplate - Config.lua
-- Settings UI with StyleLib TreeMenu (/dnp)
----------------------------------------------------------------------
local ADDON_NAME, ns = ...

local SL   = ns.SL
local FLAT = ns.FLAT
local FONT = ns.FONT

local ADDON_LABEL = "Nameplate"
local CONFIG_WIDTH  = 600
local CONFIG_HEIGHT = 500

local configFrame  -- main frame reference

----------------------------------------------------------------------
-- Helper: create widget with auto DB binding -- [NAMEPLATE]
----------------------------------------------------------------------
local function CreateCheckbox(parent, label, dbPath, onChange)
    if not SL or not SL.CreateCheckbox then return end
    local keys = { strsplit(".", dbPath) }
    local function GetDB()
        local t = ns.db
        for _, k in ipairs(keys) do t = t and t[k] end
        return t
    end
    local function SetDB(val)
        local t = ns.db
        for i = 1, #keys - 1 do t = t[keys[i]] end
        t[keys[#keys]] = val
        if onChange then onChange(val) end
        ns.UpdateAllPlates()
    end
    return SL.CreateCheckbox(parent, ADDON_LABEL, label, GetDB(), {
        onChange = SetDB,
    })
end

local function CreateSlider(parent, label, min, max, step, dbPath, onChange)
    if not SL or not SL.CreateSlider then return end
    local keys = { strsplit(".", dbPath) }
    local function GetDB()
        local t = ns.db
        for _, k in ipairs(keys) do t = t and t[k] end
        return t
    end
    local function SetDB(val)
        local t = ns.db
        for i = 1, #keys - 1 do t = t[keys[i]] end
        t[keys[#keys]] = val
        if onChange then onChange(val) end
        ns.UpdateAllPlates()
    end
    return SL.CreateSlider(parent, ADDON_LABEL, label, min, max, step, GetDB(), {
        onChange = SetDB,
    })
end

local function CreateDropdown(parent, label, options, dbPath, onChange)
    if not SL or not SL.CreateDropdown then return end
    local keys = { strsplit(".", dbPath) }
    local function GetDB()
        local t = ns.db
        for _, k in ipairs(keys) do t = t and t[k] end
        return t
    end
    local function SetDB(val)
        local t = ns.db
        for i = 1, #keys - 1 do t = t[keys[i]] end
        t[keys[#keys]] = val
        if onChange then onChange(val) end
        ns.UpdateAllPlates()
    end
    return SL.CreateDropdown(parent, ADDON_LABEL, label, options, GetDB(), {
        onChange = SetDB,
    })
end

----------------------------------------------------------------------
-- Vertical layout helper -- [NAMEPLATE]
----------------------------------------------------------------------
local function LayoutY(parent, widgets, startY, gapOverride)
    local gap = gapOverride or 8
    local y = startY or -10
    for _, w in ipairs(widgets) do
        if w then
            w:ClearAllPoints()
            w:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
            local h = w:GetHeight()
            if h and h > 0 then
                y = y - h - gap
            else
                y = y - 30 - gap
            end
        end
    end
    return y
end

----------------------------------------------------------------------
-- Page builders -- [NAMEPLATE]
----------------------------------------------------------------------
local pageBuilders = {}

-- General -- [NAMEPLATE]
pageBuilders["general"] = function(page)
    local w = {}

    if SL and SL.CreateSectionHeader then
        w[#w+1] = SL.CreateSectionHeader(page, ADDON_LABEL, "일반 설정", { isFirst = true })
    end

    w[#w+1] = CreateCheckbox(page, "네임플레이트 활성화", "general.enabled")
    w[#w+1] = CreateCheckbox(page, "아군 네임플레이트 클릭 통과", "general.clickThruFriend")
    w[#w+1] = CreateCheckbox(page, "화면 고정", "general.clampToScreen")

    LayoutY(page, w)
end

-- Enemy Health Bar -- [NAMEPLATE]
pageBuilders["enemy"] = function(page)
    local w = {}

    if SL and SL.CreateSectionHeader then
        w[#w+1] = SL.CreateSectionHeader(page, ADDON_LABEL, "적 네임플레이트", { isFirst = true })
    end

    w[#w+1] = CreateSlider(page, "너비", 60, 200, 1, "healthBar.enemy.width")
    w[#w+1] = CreateSlider(page, "높이", 4, 30, 1, "healthBar.enemy.height")

    if SL and SL.CreateSeparator then
        w[#w+1] = SL.CreateSeparator(page)
    end

    if SL and SL.CreateSectionHeader then
        w[#w+1] = SL.CreateSectionHeader(page, ADDON_LABEL, "색상")
    end

    w[#w+1] = CreateCheckbox(page, "반응 색상 (적/중립/아군)", "healthBar.colorByReaction")
    w[#w+1] = CreateCheckbox(page, "플레이어 클래스 색상", "healthBar.colorByClass")
    w[#w+1] = CreateCheckbox(page, "위협 색상 (위협 모듈 필요)", "healthBar.colorByThreat")
    w[#w+1] = CreateCheckbox(page, "부드러운 값 변화", "healthBar.smoothing")

    LayoutY(page, w)
end

-- Friendly Health Bar -- [NAMEPLATE]
pageBuilders["friendly"] = function(page)
    local w = {}

    if SL and SL.CreateSectionHeader then
        w[#w+1] = SL.CreateSectionHeader(page, ADDON_LABEL, "아군 네임플레이트", { isFirst = true })
    end

    w[#w+1] = CreateSlider(page, "너비", 40, 200, 1, "healthBar.friendly.width")
    w[#w+1] = CreateSlider(page, "높이", 2, 20, 1, "healthBar.friendly.height")

    LayoutY(page, w)
end

-- Cast Bar -- [NAMEPLATE]
pageBuilders["castBar"] = function(page)
    local w = {}

    if SL and SL.CreateSectionHeader then
        w[#w+1] = SL.CreateSectionHeader(page, ADDON_LABEL, "캐스트바", { isFirst = true })
    end

    w[#w+1] = CreateCheckbox(page, "캐스트바 표시", "castBar.enabled")
    w[#w+1] = CreateSlider(page, "높이", 4, 20, 1, "castBar.height")
    w[#w+1] = CreateSlider(page, "아이콘 크기", 8, 30, 1, "castBar.iconSize")
    w[#w+1] = CreateCheckbox(page, "차단불가 실드 표시", "castBar.showShield")
    w[#w+1] = CreateCheckbox(page, "시전 시간 표시", "castBar.showTimer")
    w[#w+1] = CreateCheckbox(page, "주문 이름 표시", "castBar.showSpellName")

    LayoutY(page, w)
end

-- Threat -- [NAMEPLATE]
pageBuilders["threat"] = function(page)
    local w = {}

    if SL and SL.CreateSectionHeader then
        w[#w+1] = SL.CreateSectionHeader(page, ADDON_LABEL, "위협", { isFirst = true })
    end

    w[#w+1] = CreateCheckbox(page, "위협 시스템 활성화", "threat.enabled")
    w[#w+1] = CreateCheckbox(page, "역할별 자동 색상", "threat.useRoleColor")

    if SL and SL.CreateSeparator then
        w[#w+1] = SL.CreateSeparator(page)
    end

    if SL and SL.CreateSectionHeader then
        w[#w+1] = SL.CreateSectionHeader(page, ADDON_LABEL, "현재 역할")
    end

    -- Role indicator (read-only)
    local roleText = page:CreateFontString(nil, "OVERLAY")
    roleText:SetFont(FONT, 12, "OUTLINE")
    local roleLabel = ns.playerIsTank and "|cff20cc20탱커|r" or
                      (ns.playerRole == "HEALER" and "|cff2080cc힐러|r" or "|cffcc2020딜러|r")
    roleText:SetText("감지된 역할: " .. roleLabel)
    w[#w+1] = roleText

    LayoutY(page, w)
end

-- Auras -- [NAMEPLATE]
pageBuilders["auras"] = function(page)
    local w = {}

    if SL and SL.CreateSectionHeader then
        w[#w+1] = SL.CreateSectionHeader(page, ADDON_LABEL, "디버프/버프", { isFirst = true })
    end

    w[#w+1] = CreateCheckbox(page, "아우라 표시", "auras.enabled")
    w[#w+1] = CreateCheckbox(page, "내 디버프만 표시", "auras.myDebuffsOnly")
    w[#w+1] = CreateSlider(page, "최대 표시 개수", 1, 15, 1, "auras.maxAuras")
    w[#w+1] = CreateSlider(page, "아이콘 크기", 10, 40, 1, "auras.iconSize")
    w[#w+1] = CreateSlider(page, "간격", 0, 10, 1, "auras.spacing")
    w[#w+1] = CreateCheckbox(page, "쿨다운 표시", "auras.showCooldown")
    w[#w+1] = CreateCheckbox(page, "중첩 수 표시", "auras.showStacks")

    LayoutY(page, w)
end

-- Text -- [NAMEPLATE]
pageBuilders["text"] = function(page)
    local w = {}

    if SL and SL.CreateSectionHeader then
        w[#w+1] = SL.CreateSectionHeader(page, ADDON_LABEL, "이름 텍스트", { isFirst = true })
    end

    w[#w+1] = CreateCheckbox(page, "이름 표시", "text.name.enabled")
    w[#w+1] = CreateSlider(page, "이름 글자 크기", 6, 20, 1, "text.name.fontSize")
    w[#w+1] = CreateSlider(page, "이름 최대 길이", 5, 40, 1, "text.name.maxLength")

    if SL and SL.CreateSeparator then
        w[#w+1] = SL.CreateSeparator(page)
    end

    if SL and SL.CreateSectionHeader then
        w[#w+1] = SL.CreateSectionHeader(page, ADDON_LABEL, "체력 텍스트")
    end

    w[#w+1] = CreateCheckbox(page, "체력 텍스트 표시", "text.health.enabled")
    w[#w+1] = CreateSlider(page, "체력 글자 크기", 6, 16, 1, "text.health.fontSize")
    w[#w+1] = CreateDropdown(page, "체력 형식", {
        { value = "CURRENT",         label = "현재값 (예: 1.2M)" },
        { value = "PERCENT",         label = "퍼센트 (예: 85%)" },
        { value = "CURRENT_PERCENT", label = "현재값 + 퍼센트" },
        { value = "CURRENT_MAX",     label = "현재값 / 최대값" },
        { value = "DEFICIT",         label = "부족량 (예: -200K)" },
        { value = "NONE",            label = "표시 안 함" },
    }, "text.health.format")

    if SL and SL.CreateSeparator then
        w[#w+1] = SL.CreateSeparator(page)
    end

    if SL and SL.CreateSectionHeader then
        w[#w+1] = SL.CreateSectionHeader(page, ADDON_LABEL, "레벨 텍스트")
    end

    w[#w+1] = CreateCheckbox(page, "레벨 표시", "text.level.enabled")
    w[#w+1] = CreateSlider(page, "레벨 글자 크기", 6, 16, 1, "text.level.fontSize")
    w[#w+1] = CreateCheckbox(page, "난이도 색상", "text.level.colorByDifficulty")

    LayoutY(page, w)
end

-- Target -- [NAMEPLATE]
pageBuilders["target"] = function(page)
    local w = {}

    if SL and SL.CreateSectionHeader then
        w[#w+1] = SL.CreateSectionHeader(page, ADDON_LABEL, "대상 표시", { isFirst = true })
    end

    w[#w+1] = CreateCheckbox(page, "대상 강조 테두리", "target.highlight")
    w[#w+1] = CreateCheckbox(page, "화살표 표시", "target.arrowIndicator")
    w[#w+1] = CreateSlider(page, "대상 스케일", 1.0, 1.5, 0.05, "target.scale")

    LayoutY(page, w)
end

----------------------------------------------------------------------
-- Tree menu data -- [NAMEPLATE]
----------------------------------------------------------------------
local menuData = {
    { text = "일반",           key = "general"  },
    { text = "적 네임플레이트", key = "enemy"    },
    { text = "아군 네임플레이트", key = "friendly" },
    { text = "캐스트바",       key = "castBar"  },
    { text = "위협",           key = "threat"   },
    { text = "디버프/버프",    key = "auras"    },
    { text = "텍스트",         key = "text"     },
    { text = "대상 표시",      key = "target"   },
}

----------------------------------------------------------------------
-- Create config frame -- [NAMEPLATE]
----------------------------------------------------------------------
local function CreateConfigFrame()
    if configFrame then return configFrame end

    -- Use StyleLib settings panel if available -- [NAMEPLATE]
    if SL and SL.CreateSettingsPanel then
        configFrame = SL.CreateSettingsPanel(ADDON_LABEL, "DDingUI Nameplate", "1.0.0", {
            width  = CONFIG_WIDTH,
            height = CONFIG_HEIGHT,
        })
    else
        -- Fallback: plain frame
        configFrame = CreateFrame("Frame", "DDingUI_NameplateConfig", UIParent, "BackdropTemplate")
        configFrame:SetSize(CONFIG_WIDTH, CONFIG_HEIGHT)
        configFrame:SetPoint("CENTER")
        configFrame:SetBackdrop({
            bgFile   = FLAT,
            edgeFile = FLAT,
            edgeSize = 1,
        })
        local bgColor = ns.GetSLColor("bg.main")
        configFrame:SetBackdropColor(ns.UnpackColor(bgColor))
        local borderColor = ns.GetSLColor("border.default")
        configFrame:SetBackdropBorderColor(ns.UnpackColor(borderColor))
        configFrame:SetMovable(true)
        configFrame:EnableMouse(true)
        configFrame:RegisterForDrag("LeftButton")
        configFrame:SetScript("OnDragStart", configFrame.StartMoving)
        configFrame:SetScript("OnDragStop", configFrame.StopMovingOrSizing)
        configFrame:SetFrameStrata("DIALOG")
        configFrame:SetClampedToScreen(true)

        -- Title
        local title = configFrame:CreateFontString(nil, "OVERLAY")
        title:SetFont(FONT, 14, "OUTLINE")
        title:SetPoint("TOP", configFrame, "TOP", 0, -10)
        title:SetText("|cff8855ddDDingUI Nameplate|r")

        -- Close button
        local close = CreateFrame("Button", nil, configFrame, "UIDismissButtonTemplate")
        close:SetPoint("TOPRIGHT", configFrame, "TOPRIGHT", -2, -2)
        close:SetScript("OnClick", function() configFrame:Hide() end)
    end

    configFrame:Hide()

    -- Content area -- [NAMEPLATE]
    local content = configFrame.contentArea or configFrame
    local currentPage = nil

    -- Build tree menu if StyleLib available -- [NAMEPLATE]
    if SL and SL.CreateTreeMenu then
        local tree = SL.CreateTreeMenu(configFrame, ADDON_LABEL, menuData, {
            onSelect = function(key)
                if currentPage then currentPage:Hide() end
                if not configFrame._pages then configFrame._pages = {} end

                if not configFrame._pages[key] then
                    local page = CreateFrame("Frame", nil, content)
                    page:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
                    page:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
                    if pageBuilders[key] then
                        pageBuilders[key](page)
                    end
                    configFrame._pages[key] = page
                end

                currentPage = configFrame._pages[key]
                currentPage:Show()
            end,
        })
    else
        -- Fallback: simple button navigation -- [NAMEPLATE]
        local yOff = -35
        for _, item in ipairs(menuData) do
            local btn = CreateFrame("Button", nil, configFrame)
            btn:SetSize(120, 22)
            btn:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 10, yOff)

            local btnText = btn:CreateFontString(nil, "OVERLAY")
            btnText:SetFont(FONT, 11, "OUTLINE")
            btnText:SetAllPoints(btn)
            btnText:SetText(item.text)
            btnText:SetJustifyH("LEFT")
            local textColor = ns.GetSLColor("text.normal")
            btnText:SetTextColor(ns.UnpackColor(textColor))

            btn:SetScript("OnClick", function()
                if currentPage then currentPage:Hide() end
                if not configFrame._pages then configFrame._pages = {} end

                if not configFrame._pages[item.key] then
                    local page = CreateFrame("Frame", nil, configFrame)
                    page:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 140, -35)
                    page:SetPoint("BOTTOMRIGHT", configFrame, "BOTTOMRIGHT", -10, 10)
                    if pageBuilders[item.key] then
                        pageBuilders[item.key](page)
                    end
                    configFrame._pages[item.key] = page
                end

                currentPage = configFrame._pages[item.key]
                currentPage:Show()
            end)

            yOff = yOff - 24
        end
    end

    -- ESC to close
    tinsert(UISpecialFrames, configFrame:GetName() or "DDingUI_NameplateConfig")

    return configFrame
end

----------------------------------------------------------------------
-- Toggle config -- [NAMEPLATE]
----------------------------------------------------------------------
function ns.ToggleConfig()
    local frame = CreateConfigFrame()
    if not frame then return end
    if frame.IsShown and frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end
