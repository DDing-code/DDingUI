--[[
    DDingToolKit - Config_UI.lua
    StyleLib 기반 설정 UI 렌더링 엔진
    -- [REFACTOR] StyleLib 리팩토링 Phase 2
]]
local addonName, ns = ...
local L = ns.L

-- StyleLib 참조
local Lib = LibStub("DDingUI-StyleLib-1.0")
local C    = Lib.Colors
local S    = Lib.Spacing
local F    = Lib.Font
local Widgets = ns.ToolkitControls or Lib

local ADDON_KEY = "MJToolkit"  -- StyleLib 악센트 프리셋 키
local SOLID     = Lib.Textures and Lib.Textures.flat or "Interface\\Buttons\\WHITE8x8" -- [12.0.1]

-- LibSharedMedia (옵셔널)
local LSM = LibStub("LibSharedMedia-3.0", true)

------------------------------------------------------
-- 모듈 스코프 상태
------------------------------------------------------
local ConfigUI = {}
ns.ConfigUI = ConfigUI

local settingsPanel     -- Lib.CreateSettingsPanel 결과
local panelContainers = {} -- key → Frame
local activePanel       -- 현재 선택된 패널 키
local panelSectionState = {}
local activeDetailPreview
local detailPreviewRefreshTimer
local DETAIL_PREVIEW_CONTEXT = { source = "config" }

local function QueueDetailPreviewRefresh()
    if not activeDetailPreview or not activeDetailPreview.module then return end
    if detailPreviewRefreshTimer then
        detailPreviewRefreshTimer:Cancel()
    end

    local state = activeDetailPreview
    detailPreviewRefreshTimer = C_Timer.NewTimer(0.06, function()
        detailPreviewRefreshTimer = nil
        if activeDetailPreview ~= state then return end

        local module = state.module
        if module.RefreshEditPreview then
            module:RefreshEditPreview(state.context)
        elseif module.ExitEditPreview and module.EnterEditPreview then
            module:ExitEditPreview(state.context)
            module:EnterEditPreview(state.context)
        end
    end)
end

------------------------------------------------------
-- ReloadUI 팝업
------------------------------------------------------
StaticPopupDialogs["DDINGTOOLKIT_RELOAD_CONFIRM"] = {
    text = L["RELOAD_UI_CONFIRM"] or "UI reload required.\nReload now?",
    button1 = ACCEPT or "OK",
    button2 = CANCEL or "Cancel",
    OnAccept = function() ReloadUI() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

------------------------------------------------------
-- 유틸리티
------------------------------------------------------
local function u(t) return unpack(t) end

local function LT(key, fallback)
    local value = L and rawget(L, key)
    if type(value) == "string" and value ~= "" then return value end
    return fallback
end

local function EnableRightClickMouselook(frame)
    if ns.EnableRightClickMouselook then
        ns:EnableRightClickMouselook(frame)
    end
end

local function ResolveOptions(options)
    if type(options) == "table" then return options end
    if options == "soundChannels"  then return ns:GetSoundChannelOptions() end
    if options == "alertPositions" then return ns:GetAlertPositionOptions() end
    if options == "alignOptions"   then return ns:GetAlignOptions() end
    if options == "chatTypes"      then return ns:GetChatTypeOptions() end
    if options == "cursorTrailTextures" then return ns.CursorTrailTextureList or {} end
    return {}
end

local function GetValue(setting)
    local val = ns:GetDBValue(setting.key)
    if setting.invert then val = not val end
    return val
end

local function SetValue(setting, value)
    if setting.invert then value = not value end
    ns:SetDBValue(setting.key, value)
    if setting.onChange then setting.onChange(value) end
    QueueDetailPreviewRefresh()
    if setting.reloadRequired then
        StaticPopup_Show("DDINGTOOLKIT_RELOAD_CONFIRM")
    end
end

--- 텍스트 프레임 래퍼 (숨기기 가능하도록 Frame 안에 FontString)
local function MakeTextFrame(parent, text, color, size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(16)
    local fs = f:CreateFontString(nil, "OVERLAY")
    fs:SetFont(F.path, size or F.small, "")
    fs:SetTextColor(u(color or C.text.dim))
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    fs:SetText(text or "")
    fs:SetPoint("TOPLEFT")
    fs:SetPoint("TOPRIGHT")
    f.text = fs
    -- 높이를 텍스트에 맞춤 (딜레이)
    f:SetScript("OnShow", function(self)
        local h = self.text:GetStringHeight()
        self:SetHeight(math.max(h, 12))
    end)
    C_Timer.After(0, function()
        if f:IsShown() and f.text then
            f:SetHeight(math.max(f.text:GetStringHeight(), 12))
        end
    end)
    return f
end

------------------------------------------------------
-- LSM 기반 위젯: Sound 드롭다운 + 커스텀 경로 -- [12.0.1]
------------------------------------------------------
local function CreateSoundWidget(parent, setting)
    -- 컨테이너 (드롭다운 + 커스텀 경로 + 테스트 버튼)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(560, setting.customPathKey and 68 or 30)

    -- 1) LSM 사운드 드롭다운
    local options = {}
    if setting.defaultLabel then
        options[#options + 1] = { text = setting.defaultLabel, value = "" }
    end
    if LSM then
        local sounds = LSM:HashTable("sound")
        local sorted = {}
        for name in pairs(sounds) do sorted[#sorted + 1] = name end
        table.sort(sorted)
        for _, name in ipairs(sorted) do
            options[#options + 1] = { text = name, value = sounds[name] }
        end
    end
    local current = ns:GetDBValue(setting.key)
    local dropdown = Widgets.CreateDropdown(container, ADDON_KEY, setting.label or "", options, current, {
        width = 220,
        mediaType = "sound",
        searchable = true,
        tooltip = setting.desc,
        onChange = function(value)
            ns:SetDBValue(setting.key, value)
            if value and value ~= "" then
                local channelKey = setting.channelKey or setting.key:gsub("soundFile$", "soundChannel")
                PlaySoundFile(value, ns:GetDBValue(channelKey) or "Master")
            end
            if setting.onChange then setting.onChange(value) end
            QueueDetailPreviewRefresh()
        end,
    })
    dropdown:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    dropdown:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)

    -- 2) 커스텀 경로 EditBox -- [12.0.1]
    local customKey = setting.customPathKey
    if customKey then
        local customInput = Widgets.CreateInputField(
            container,
            ADDON_KEY,
            L and L["SOUND_CUSTOM_PATH"] or "Custom path",
            ns:GetDBValue(customKey) or "",
            {
                inputWidth = 230,
                maxLetters = 256,
                onChange = function(value)
                    ns:SetDBValue(customKey, value)
                    if setting.customPathOnChange and setting.onChange then
                        setting.onChange(value)
                    end
                    QueueDetailPreviewRefresh()
                end,
            }
        )
        customInput:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -36)
        customInput:SetPoint("TOPRIGHT", container, "TOPRIGHT", -82, -36)

        local testBtn = Widgets.CreateButton(container, ADDON_KEY, L and L["SOUND_TEST"] or "Test", function()
            local customPath = ns:GetDBValue(customKey)
            local soundFile = ns:GetDBValue(setting.key)
            local channelKey = setting.channelKey or setting.key:gsub("soundFile$", "soundChannel")
            local channel = ns:GetDBValue(channelKey) or "Master"
            ns:PlaySound(soundFile, channel, customPath)
        end, { width = 72, height = 24 })
        testBtn:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, -39)

        container:SetHeight(68)
    end

    return container
end

-- 하위 호환: 기존 sound 타입 위젯용 래퍼
local function CreateSoundDropdown(parent, setting)
    return CreateSoundWidget(parent, setting)
end

------------------------------------------------------
-- LSM 기반 위젯: Font 드롭다운
------------------------------------------------------
local function CreateFontDropdown(parent, setting)
    local options = {}
    if LSM then
        local fonts = LSM:HashTable("font")
        local sorted = {}
        for name in pairs(fonts) do sorted[#sorted + 1] = name end
        table.sort(sorted)
        for _, name in ipairs(sorted) do
            options[#options + 1] = { text = name, value = fonts[name] }
        end
    end
    if #options == 0 then
        options[1] = { text = "Default", value = F.default or "Fonts\\FRIZQT__.TTF" } -- [12.0.1]
    end
    local current = ns:GetDBValue(setting.key)
    return Widgets.CreateDropdown(parent, ADDON_KEY, setting.label or "", options, current, {
        width = 220,
        mediaType = "font",
        searchable = true,
        tooltip = setting.desc,
        onChange = function(value)
            ns:SetDBValue(setting.key, value)
            if setting.onChange then setting.onChange(value) end
            QueueDetailPreviewRefresh()
        end,
    })
end

------------------------------------------------------
-- LSM 기반 위젯: StatusBar Texture 드롭다운
------------------------------------------------------
local function CreateStatusBarDropdown(parent, setting)
    local options = {}
    if LSM then
        local bars = LSM:HashTable("statusbar")
        local sorted = {}
        for name in pairs(bars) do sorted[#sorted + 1] = name end
        table.sort(sorted)
        for _, name in ipairs(sorted) do
            options[#options + 1] = { text = name, value = bars[name] }
        end
    end
    if #options == 0 then
        options[1] = { text = "Default", value = "Interface\\TargetingFrame\\UI-StatusBar" }
    end
    local current = ns:GetDBValue(setting.key)
    return Widgets.CreateDropdown(parent, ADDON_KEY, setting.label or "", options, current, {
        width = 220,
        mediaType = "statusbar",
        searchable = true,
        tooltip = setting.desc,
        onChange = function(value)
            ns:SetDBValue(setting.key, value)
            if setting.onChange then setting.onChange(value) end
            QueueDetailPreviewRefresh()
        end,
    })
end

------------------------------------------------------
-- 위젯: Color 버튼
------------------------------------------------------
local GRADIENT_BAR_COLOR_KEYS = {
    ["profile.StasisTracker.timerBarColor"] = true,
    ["profile.StasisTracker.warningColor"] = true,
    ["profile.BloodlustTimer.activeBarColor"] = true,
    ["profile.BloodlustTimer.exhaustionBarColor"] = true,
    ["profile.FocusInterrupt.interruptibleColor"] = true,
    ["profile.FocusInterrupt.notInterruptibleColor"] = true,
    ["profile.FocusInterrupt.interruptedColor"] = true,
}

local function CreateColorButton(parent, setting)
    local supportsGradient = setting.supportsGradient == true or GRADIENT_BAR_COLOR_KEYS[setting.key] == true

    local function ReadColor()
        local c = ns:GetDBValue(setting.key)
        if not c then return { 1, 1, 1, 1 } end
        if setting.colorFormat == "rgb_object" then
            return { c.r or 1, c.g or 1, c.b or 1, 1 }
        end
        local result = { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
        if supportsGradient and Lib.CopyBarColorMetadata then
            Lib.CopyBarColorMetadata(result, c)
        end
        return result
    end

    local function NotifyChanged(value)
        if setting.onChange then setting.onChange(value) end
        QueueDetailPreviewRefresh()
    end

    local widget = Widgets.CreateColor(parent, ADDON_KEY, setting.label or "", ReadColor(), {
        hasAlpha = setting.hasAlpha,
        tooltip = setting.desc,
        supportsGradient = supportsGradient,
        onChange = function(r, g, b, a)
            local previous = ns:GetDBValue(setting.key)
            local nextColor
            if setting.colorFormat == "rgb_object" then
                nextColor = { r = r, g = g, b = b }
            elseif setting.hasAlpha then
                nextColor = { r, g, b, a }
            else
                nextColor = { r, g, b }
            end
            if supportsGradient and Lib.CopyBarColorMetadata then
                Lib.CopyBarColorMetadata(nextColor, previous)
            end
            ns:SetDBValue(setting.key, nextColor)
            NotifyChanged(nextColor)
        end,
        onGradientChange = function(colorSpec)
            local nextColor = {
                colorSpec[1] or 1,
                colorSpec[2] or 1,
                colorSpec[3] or 1,
                colorSpec[4] or 1,
            }
            if Lib.CopyBarColorMetadata then
                Lib.CopyBarColorMetadata(nextColor, colorSpec)
            end
            ns:SetDBValue(setting.key, nextColor)
            NotifyChanged(nextColor)
        end,
    })
    if setting.compactWidth then
        widget:SetWidth(setting.compactWidth)
    end
    return widget
end

------------------------------------------------------
-- 모듈 비활성화 오버레이 (회색 처리 + 클릭 차단) -- [REFACTOR]
------------------------------------------------------
local function UpdateModuleOverlay(container, enabled)
    if not container._moduleOverlay then return end
    if enabled then
        container._moduleOverlay:Hide()
    else
        container._moduleOverlay:Show()
    end
end

local function CreateModuleOverlay(container, yStart)
    if container._moduleOverlay then
        container._moduleOverlay:ClearAllPoints()
        container._moduleOverlay:SetPoint("TOPLEFT", container, "TOPLEFT", 0, yStart)
        container._moduleOverlay:SetPoint("BOTTOMRIGHT")
        return container._moduleOverlay
    end
    local overlay = CreateFrame("Frame", nil, container)
    overlay:SetPoint("TOPLEFT", container, "TOPLEFT", 0, yStart)
    overlay:SetPoint("BOTTOMRIGHT")
    overlay:SetFrameLevel(container:GetFrameLevel() + 100)
    overlay:EnableMouse(true)
    overlay:SetScript("OnMouseDown", function() end)
    overlay:SetScript("OnMouseUp", function() end)
    overlay:SetScript("OnMouseWheel", function() end)
    EnableRightClickMouselook(overlay)
    local tex = overlay:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetColorTexture(0, 0, 0, 0.45)
    container._moduleOverlay = overlay
    return overlay
end

local function SetButtonText(button, text)
    if not button then return end
    if button.label then
        button.label:SetText(text)
    elseif button.SetText then
        button:SetText(text)
    end
end

local function GetPanelModule(panelKey)
    local moduleName = ns.ConfigModuleMap and ns.ConfigModuleMap[panelKey]
    local module = moduleName and ns.modules and ns.modules[moduleName]
    return moduleName, module
end

local function StopDetailPreview()
    if detailPreviewRefreshTimer then
        detailPreviewRefreshTimer:Cancel()
        detailPreviewRefreshTimer = nil
    end

    local state = activeDetailPreview
    if not state then return end

    if state.module and state.module.ExitEditPreview then
        state.module:ExitEditPreview(state.context)
    end
    SetButtonText(state.button, LT("DETAIL_PREVIEW_START", "Start preview"))
    activeDetailPreview = nil
end

local function ToggleDetailPreview(panelKey, button)
    if activeDetailPreview and activeDetailPreview.panelKey == panelKey then
        StopDetailPreview()
        return
    end

    StopDetailPreview()

    local _, module = GetPanelModule(panelKey)
    if not module then return end

    if module.EnterEditPreview and module.ExitEditPreview then
        module:EnterEditPreview(DETAIL_PREVIEW_CONTEXT)
        activeDetailPreview = {
            panelKey = panelKey,
            module = module,
            button = button,
            context = DETAIL_PREVIEW_CONTEXT,
        }
        SetButtonText(button, LT("DETAIL_PREVIEW_STOP", "Stop preview"))
    elseif module.TriggerAlert then
        module:TriggerAlert(true)
    elseif module.TestAlert then
        module:TestAlert()
    end
end

local function ModuleSupportsPreview(panelKey)
    local _, module = GetPanelModule(panelKey)
    if not module then return false end
    return (module.EnterEditPreview and module.ExitEditPreview)
        or module.TriggerAlert
        or module.TestAlert
end

local function CreateDetailPreview(parent, panelKey)
    if not ModuleSupportsPreview(panelKey) then return nil end

    local preview = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    preview:SetHeight(76)
    preview:SetBackdrop({
        bgFile = SOLID,
        edgeFile = SOLID,
        edgeSize = 1,
    })
    preview:SetBackdropColor(0.055, 0.058, 0.065, 0.96)
    preview:SetBackdropBorderColor(0.22, 0.23, 0.26, 0.9)

    local accent = Lib.GetAccent(ADDON_KEY)
    local marker = preview:CreateTexture(nil, "ARTWORK")
    marker:SetPoint("TOPLEFT", preview, "TOPLEFT", 0, 0)
    marker:SetPoint("BOTTOMLEFT", preview, "BOTTOMLEFT", 0, 0)
    marker:SetWidth(3)
    marker:SetColorTexture(accent[1], accent[2], accent[3], 1)

    local title = preview:CreateFontString(nil, "OVERLAY")
    title:SetFont(F.path, F.normal, "")
    title:SetTextColor(u(C.text.highlight))
    title:SetPoint("TOPLEFT", preview, "TOPLEFT", 16, -14)
    title:SetText(LT("DETAIL_PREVIEW_TITLE", "Live preview"))

    local desc = preview:CreateFontString(nil, "OVERLAY")
    desc:SetFont(F.path, F.small, "")
    desc:SetTextColor(u(C.text.dim))
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -7)
    desc:SetPoint("RIGHT", preview, "RIGHT", -170, 0)
    desc:SetJustifyH("LEFT")
    desc:SetText(LT("DETAIL_PREVIEW_DESC", "Show the real element while adjusting its settings."))

    local previewButton
    previewButton = Widgets.CreateButton(preview, ADDON_KEY,
        activeDetailPreview and activeDetailPreview.panelKey == panelKey
            and LT("DETAIL_PREVIEW_STOP", "Stop preview")
            or LT("DETAIL_PREVIEW_START", "Start preview"),
        function()
            ToggleDetailPreview(panelKey, previewButton)
        end,
        { width = 132, height = 28 }
    )
    previewButton:SetPoint("RIGHT", preview, "RIGHT", -14, 0)
    preview.previewButton = previewButton

    return preview
end

local function IsRedundantPreviewButton(setting, panelKey)
    if setting.type ~= "button" or not ModuleSupportsPreview(panelKey) then
        return false
    end

    local label = setting.label
    return label == rawget(L, "TEST_ALERT")
        or label == rawget(L, "TEST_ON_OFF")
end

local function BuildPanelSections(panelDef, usesWorkspaceHeader, panelKey)
    local sections = {}
    local current

    local function EnsureSection(label)
        if current then return current end
        current = {
            id = "general",
            label = label or LT("DETAIL_SECTION_GENERAL", "General"),
            settings = {},
        }
        sections[#sections + 1] = current
        return current
    end

    for _, setting in ipairs(panelDef.settings or {}) do
        local skipWorkspaceSetting = usesWorkspaceHeader
            and (setting.isModuleToggle or (setting.type == "header" and setting.isFirst))

        if not skipWorkspaceSetting and not IsRedundantPreviewButton(setting, panelKey) then
            if setting.type == "header" then
                current = {
                    id = "section_" .. tostring(#sections + 1),
                    label = setting.label or LT("DETAIL_SECTION_GENERAL", "General"),
                    settings = {},
                }
                sections[#sections + 1] = current
            else
                local section = EnsureSection()
                section.settings[#section.settings + 1] = setting
            end
        end
    end

    for index = #sections, 1, -1 do
        if #sections[index].settings == 0 then
            table.remove(sections, index)
        end
    end
    return sections
end

local function CreateSectionTab(parent, label, onClick)
    local tab = CreateFrame("Button", nil, parent)
    tab:SetHeight(32)
    tab:RegisterForClicks("LeftButtonUp")

    tab.bg = tab:CreateTexture(nil, "BACKGROUND")
    tab.bg:SetAllPoints()
    tab.bg:SetColorTexture(0.09, 0.092, 0.105, 0.72)

    tab.label = tab:CreateFontString(nil, "OVERLAY")
    tab.label:SetFont(F.path, F.small, "")
    tab.label:SetPoint("LEFT", tab, "LEFT", 10, 0)
    tab.label:SetPoint("RIGHT", tab, "RIGHT", -10, 0)
    tab.label:SetJustifyH("CENTER")
    tab.label:SetWordWrap(false)
    tab.label:SetText(label or "")

    tab.underline = tab:CreateTexture(nil, "ARTWORK")
    tab.underline:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 8, 0)
    tab.underline:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -8, 0)
    tab.underline:SetHeight(2)

    local accent = Lib.GetAccent(ADDON_KEY)
    function tab:SetSelected(selected)
        self.selected = selected
        self.underline:SetShown(selected)
        if selected then
            self.bg:SetColorTexture(0.14, 0.14, 0.16, 0.98)
            self.label:SetTextColor(accent[1], accent[2], accent[3], 1)
            self.underline:SetColorTexture(accent[1], accent[2], accent[3], 1)
        else
            self.bg:SetColorTexture(0.09, 0.092, 0.105, 0.72)
            self.label:SetTextColor(u(C.text.normal))
        end
    end

    tab:SetScript("OnEnter", function(self)
        if not self.selected then
            self.bg:SetColorTexture(0.13, 0.13, 0.15, 0.9)
            self.label:SetTextColor(u(C.text.highlight))
        end
    end)
    tab:SetScript("OnLeave", function(self)
        self:SetSelected(self.selected)
    end)
    tab:SetScript("OnClick", onClick)
    return tab
end

------------------------------------------------------
-- 패널 렌더러
------------------------------------------------------
local function RenderSettingsPanel(container, panelDef)
    local yOff = -S.contentPad
    local pad  = S.contentPad
    local moduleToggleEndY = nil  -- 모듈 활성화 토글 아래 Y 오프셋 추적
    local usesWorkspaceHeader = settingsPanel and settingsPanel.workspace and panelDef.moduleEnableKey

    -- 설명 텍스트
    if panelDef.desc and not (settingsPanel and settingsPanel.workspace) then
        local df = MakeTextFrame(container, panelDef.desc, C.text.dim, F.small)
        df:SetPoint("TOPLEFT", container, "TOPLEFT", pad, yOff)
        df:SetPoint("TOPRIGHT", container, "TOPRIGHT", -pad, yOff)
        -- 동적 텍스트 높이 계산
        local availW = (container:GetWidth() or 590) - pad * 2
        if availW < 100 then availW = 560 end
        df.text:SetWidth(availW)
        local textH = df.text:GetStringHeight() or 16
        yOff = yOff - math.max(textH + 12, 24)
    end

    local settings = panelDef.settings or {}

    for _, s in ipairs(settings) do
        local w  -- 생성된 위젯

        -- 새 작업공간에서는 모듈 활성화를 우측 헤더에서 제어한다.
        if usesWorkspaceHeader and (s.isModuleToggle or (s.type == "header" and s.isFirst)) then
            -- Header-owned setting.

        -- header -----------------------------------------------
        elseif s.type == "header" then
            w = Widgets.CreateSectionHeader(container, ADDON_KEY, s.label, { isFirst = s.isFirst })
            w:SetPoint("TOPLEFT", container, "TOPLEFT", pad, yOff)
            w:SetPoint("TOPRIGHT", container, "TOPRIGHT", -pad, yOff)
            yOff = yOff - w:GetHeight()

        -- separator --------------------------------------------
        elseif s.type == "separator" then
            local sep = Widgets.CreateSeparator(container)
            sep:SetPoint("TOPLEFT", container, "TOPLEFT", pad, yOff - S.controlGap)
            sep:SetPoint("TOPRIGHT", container, "TOPRIGHT", -pad, yOff - S.controlGap)
            yOff = yOff - S.controlGap * 2 - 1

        -- text (정적 텍스트) -----------------------------------
        elseif s.type == "text" then
            local tf = MakeTextFrame(container, s.label, C.text.dim, F.small)
            tf:SetPoint("TOPLEFT", container, "TOPLEFT", pad, yOff - S.controlGap)
            tf:SetPoint("TOPRIGHT", container, "TOPRIGHT", -pad, yOff - S.controlGap)
            -- 동적 텍스트 높이 계산
            local availW = (container:GetWidth() or 590) - pad * 2
            if availW < 100 then availW = 560 end
            tf.text:SetWidth(availW)
            local textH = tf.text:GetStringHeight() or 16
            yOff = yOff - S.controlGap - math.max(textH + 4, 20)

        -- toggle -----------------------------------------------
        elseif s.type == "toggle" then
            local val = GetValue(s)
            local onChangeFn
            if s.isModuleToggle and panelDef.moduleEnableKey then
                -- 모듈 활성화 토글: 오버레이 상태도 업데이트 -- [REFACTOR]
                onChangeFn = function(checked)
                    SetValue(s, checked)
                    UpdateModuleOverlay(container, checked)
                end
            else
                onChangeFn = function(checked)
                    SetValue(s, checked)
                end
            end
            w = Widgets.CreateCheckbox(container, ADDON_KEY, s.label or "", val, {
                tooltip = s.desc,
                onChange = onChangeFn,
            })
            w:SetPoint("TOPLEFT", container, "TOPLEFT", pad, yOff - S.controlGap)
            w:SetPoint("TOPRIGHT", container, "TOPRIGHT", -pad, yOff - S.controlGap)
            yOff = yOff - S.controlGap - w:GetHeight()
            -- 모듈 토글 위치 추적 -- [REFACTOR]
            if s.isModuleToggle and panelDef.moduleEnableKey then
                moduleToggleEndY = yOff
            end

        -- slider -----------------------------------------------
        elseif s.type == "slider" then
            local val = ns:GetDBValue(s.key) or s.min
            w = Widgets.CreateSlider(container, ADDON_KEY, s.label or "",
                s.min, s.max, s.step, val, {
                    tooltip = s.desc,
                    onChange = function(value)
                        ns:SetDBValue(s.key, value)
                        if s.onChange then s.onChange(value) end
                        QueueDetailPreviewRefresh()
                    end,
                })
            w:SetPoint("TOPLEFT", container, "TOPLEFT", pad, yOff - S.controlGap)
            w:SetPoint("TOPRIGHT", container, "TOPRIGHT", -pad, yOff - S.controlGap)
            yOff = yOff - S.controlGap - w:GetHeight()

        -- dropdown ---------------------------------------------
        elseif s.type == "dropdown" then
            local opts = ResolveOptions(s.options)
            local val  = ns:GetDBValue(s.key)
            w = Widgets.CreateDropdown(container, ADDON_KEY, s.label or "", opts, val, {
                width = 220,
                searchable = s.searchable,
                tooltip = s.desc,
                onChange = function(value)
                    ns:SetDBValue(s.key, value)
                    if s.onChange then s.onChange(value) end
                    QueueDetailPreviewRefresh()
                end,
            })
            w:SetPoint("TOPLEFT", container, "TOPLEFT", pad, yOff - S.controlGap)
            w:SetPoint("TOPRIGHT", container, "TOPRIGHT", -pad, yOff - S.controlGap)
            yOff = yOff - S.controlGap - w:GetHeight()

        -- input ------------------------------------------------
        elseif s.type == "input" then
            local val = ns:GetDBValue(s.key) or ""
            w = Widgets.CreateInputField(container, ADDON_KEY, s.label or "", val, {
                inputWidth = s.inputWidth or 220,
                numeric = s.numeric,
                tooltip = s.desc,
                onChange = function(text)
                    ns:SetDBValue(s.key, text or "")
                    if s.onChange then s.onChange(text) end
                    QueueDetailPreviewRefresh()
                end,
            })
            w:SetPoint("TOPLEFT", container, "TOPLEFT", pad, yOff - S.controlGap)
            w:SetPoint("TOPRIGHT", container, "TOPRIGHT", -pad, yOff - S.controlGap)
            yOff = yOff - S.controlGap - w:GetHeight()

        -- button -----------------------------------------------
        elseif s.type == "button" then
            w = Widgets.CreateButton(container, ADDON_KEY, s.label or "", function(self)
                if s.onClick then s.onClick() end
                -- refreshPanel 플래그: 버튼 클릭 후 패널 갱신
                if s.refreshPanel and activePanel then
                    ConfigUI:RefreshCurrentPanel()
                end
            end, { width = s.width or 160, tooltip = s.desc })
            w:SetPoint("TOPLEFT", container, "TOPLEFT", pad, yOff - S.controlGap)
            yOff = yOff - S.controlGap - w:GetHeight()

        -- color ------------------------------------------------
        elseif s.type == "color" then
            w = CreateColorButton(container, s)
            w:SetPoint("TOPLEFT", container, "TOPLEFT", pad, yOff - S.controlGap)
            w:SetPoint("TOPRIGHT", container, "TOPRIGHT", -pad, yOff - S.controlGap)
            yOff = yOff - S.controlGap - w:GetHeight()

        -- sound (LSM + 커스텀 경로) -- [12.0.1] -----------------
        elseif s.type == "sound" then
            w = CreateSoundDropdown(container, s)
            w:SetPoint("TOPLEFT", container, "TOPLEFT", pad, yOff - S.controlGap)
            w:SetPoint("TOPRIGHT", container, "TOPRIGHT", -pad, yOff - S.controlGap)
            yOff = yOff - S.controlGap - w:GetHeight()

        -- font (LSM) -------------------------------------------
        elseif s.type == "font" then
            w = CreateFontDropdown(container, s)
            w:SetPoint("TOPLEFT", container, "TOPLEFT", pad, yOff - S.controlGap)
            w:SetPoint("TOPRIGHT", container, "TOPRIGHT", -pad, yOff - S.controlGap)
            yOff = yOff - S.controlGap - w:GetHeight()

        -- statusbar (LSM) --------------------------------------
        elseif s.type == "statusbar" then
            w = CreateStatusBarDropdown(container, s)
            w:SetPoint("TOPLEFT", container, "TOPLEFT", pad, yOff - S.controlGap)
            w:SetPoint("TOPRIGHT", container, "TOPRIGHT", -pad, yOff - S.controlGap)
            yOff = yOff - S.controlGap - w:GetHeight()

        -- custom: colorArray (CursorTrail 색상 그리드) -----------
        elseif s.type == "custom" and s.customType == "colorArray" then
            local maxColors = s.maxColors or 10
            local colsPerRow = 2
            local btnW, btnH, btnGap = 180, 30, 8
            local gridFrame = CreateFrame("Frame", nil, container)
            gridFrame:SetSize(colsPerRow * (btnW + btnGap), math.ceil(maxColors / colsPerRow) * (btnH + btnGap))
            gridFrame:SetPoint("TOPLEFT", container, "TOPLEFT", pad, yOff - S.controlGap)

            for i = 1, maxColors do
                local row = math.ceil(i / colsPerRow) - 1
                local col = (i - 1) % colsPerRow
                local colorSetting = {
                    key = s.colorsKey .. "." .. i,
                    label = string.format(L["CURSORTRAIL_COLOR_N"] or "Color %d", i),
                    compactWidth = btnW,
                    hasAlpha = true,
                    colorFormat = nil, -- array {r,g,b,a}
                    onChange = function()
                        ns:SetDBValue("profile.CursorTrail.preset", "custom")
                    end,
                }
                local cb = CreateColorButton(gridFrame, colorSetting)
                cb:SetPoint("TOPLEFT", gridFrame, "TOPLEFT", col * (btnW + btnGap), -(row * (btnH + btnGap)))
            end

            local rows = math.ceil(maxColors / colsPerRow)
            yOff = yOff - S.controlGap - rows * (btnH + btnGap) - 4

        -- custom: cursortrail_presets (프리셋 드롭다운) --------
        elseif s.type == "custom" and s.customType == "cursortrail_presets" then
            local presetList = ns.CursorTrailPresetList or {}
            local val = ns:GetDBValue("profile.CursorTrail.preset") or "custom"
            w = Widgets.CreateDropdown(container, ADDON_KEY, L["PRESET"] or "Preset", presetList, val, {
                width = 220,
                searchable = true,
                onChange = function(value)
                    ns:SetDBValue("profile.CursorTrail.preset", value)
                    if value ~= "custom" then
                        local mod = ns.modules and ns.modules["CursorTrail"]
                        if mod and mod.ApplyPreset then
                            mod:ApplyPreset(value)
                        end
                        -- 프리셋 적용 후 패널 갱신 (색상 버튼/슬라이더 반영)
                        C_Timer.After(0.05, function()
                            ConfigUI:RefreshCurrentPanel()
                        end)
                    end
                end,
            })
            w:SetPoint("TOPLEFT", container, "TOPLEFT", pad, yOff - S.controlGap)
            w:SetPoint("TOPRIGHT", container, "TOPRIGHT", -pad, yOff - S.controlGap)
            yOff = yOff - S.controlGap - w:GetHeight()

        -- custom: 기타 미구현 ----------------------------------
        elseif s.type == "custom" then
            local cf = MakeTextFrame(container,
                "|cFF666666[Custom: " .. (s.customType or "?") .. "]|r",
                C.text.disabled, F.small)
            cf:SetPoint("TOPLEFT", container, "TOPLEFT", pad, yOff - S.controlGap)
            cf:SetPoint("TOPRIGHT", container, "TOPRIGHT", -pad, yOff - S.controlGap)
            yOff = yOff - S.controlGap - 20
        end
    end

    -- 컨테이너 높이 저장
    container._contentHeight = math.abs(yOff) + pad
    container:SetHeight(container._contentHeight)

    -- 모듈 비활성화 오버레이 생성 -- [REFACTOR]
    if panelDef.moduleEnableKey and (moduleToggleEndY or usesWorkspaceHeader) then
        CreateModuleOverlay(container, moduleToggleEndY or 0)
        local isEnabled = ns:GetDBValue(panelDef.moduleEnableKey)
        UpdateModuleOverlay(container, isEnabled == true)
    end
end

local function RenderSectionedPanel(container, panelDef, panelKey)
    local usesWorkspaceHeader = settingsPanel and settingsPanel.workspace and panelDef.moduleEnableKey
    local sections = BuildPanelSections(panelDef, usesWorkspaceHeader, panelKey)
    if #sections < 2 then
        local preview = CreateDetailPreview(container, panelKey)
        if not preview then
            RenderSettingsPanel(container, panelDef)
            return
        end

        local pad = S.contentPad
        preview:SetPoint("TOPLEFT", container, "TOPLEFT", pad, -pad)
        preview:SetPoint("TOPRIGHT", container, "TOPRIGHT", -pad, -pad)

        local body = CreateFrame("Frame", nil, container)
        local bodyTop = -pad - preview:GetHeight() - 14
        body:SetPoint("TOPLEFT", container, "TOPLEFT", 0, bodyTop)
        body:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, bodyTop)
        RenderSettingsPanel(body, {
            settings = sections[1] and sections[1].settings or panelDef.settings,
        })

        container._contentHeight = math.abs(bodyTop) + (body._contentHeight or 0) + pad
        container:SetHeight(container._contentHeight)
        CreateModuleOverlay(container, 0)
        UpdateModuleOverlay(container, ns:GetDBValue(panelDef.moduleEnableKey) == true)
        return
    end

    local pad = S.contentPad
    local yOff = -pad
    local preview = CreateDetailPreview(container, panelKey)
    if preview then
        preview:SetPoint("TOPLEFT", container, "TOPLEFT", pad, yOff)
        preview:SetPoint("TOPRIGHT", container, "TOPRIGHT", -pad, yOff)
        yOff = yOff - preview:GetHeight() - 14
    end

    local sectionTitle = MakeTextFrame(
        container,
        LT("DETAIL_SECTION_TITLE", "Settings"),
        C.text.highlight,
        F.normal
    )
    sectionTitle:SetPoint("TOPLEFT", container, "TOPLEFT", pad, yOff)
    sectionTitle:SetPoint("TOPRIGHT", container, "TOPRIGHT", -pad, yOff)
    yOff = yOff - 24

    local availableWidth = math.max((container:GetWidth() or 720) - pad * 2, 480)
    local columnCount = math.min(#sections, 4)
    if #sections == 5 then columnCount = 3 end
    local gap = 6
    local tabWidth = math.floor((availableWidth - (columnCount - 1) * gap) / columnCount)
    local rowCount = math.ceil(#sections / columnCount)
    local tabAreaHeight = rowCount * 32 + (rowCount - 1) * gap
    local tabs = {}
    local bodies = {}

    local selectedId = panelSectionState[panelKey]
    local selectedIndex = 1
    for index, section in ipairs(sections) do
        if section.id == selectedId then
            selectedIndex = index
            break
        end
    end

    local bodyTop = yOff - tabAreaHeight - 12
    local function EnsureSectionBody(index)
        if bodies[index] then return bodies[index] end
        local body = CreateFrame("Frame", nil, container)
        body:SetPoint("TOPLEFT", container, "TOPLEFT", 0, bodyTop)
        body:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, bodyTop)
        RenderSettingsPanel(body, { settings = sections[index].settings })
        body:Hide()
        bodies[index] = body
        return body
    end

    local function ActivateSection(index)
        selectedIndex = index
        panelSectionState[panelKey] = sections[index].id
        for tabIndex, tab in ipairs(tabs) do
            tab:SetSelected(tabIndex == index)
        end
        local selectedBody = EnsureSectionBody(index)
        for bodyIndex, body in pairs(bodies) do
            body:SetShown(bodyIndex == index)
        end

        local contentHeight = math.abs(bodyTop)
            + (selectedBody._contentHeight or 0)
            + pad
        container._contentHeight = contentHeight
        container:SetHeight(contentHeight)
        if settingsPanel and settingsPanel.contentChild and activePanel == panelKey then
            settingsPanel.contentChild:SetHeight(contentHeight)
        end
    end

    for index, section in ipairs(sections) do
        local sectionIndex = index
        local row = math.floor((index - 1) / columnCount)
        local column = (index - 1) % columnCount
        local tab = CreateSectionTab(container, section.label, function()
            ActivateSection(sectionIndex)
        end)
        tab:SetWidth(tabWidth)
        tab:SetPoint(
            "TOPLEFT",
            container,
            "TOPLEFT",
            pad + column * (tabWidth + gap),
            yOff - row * (32 + gap)
        )
        tabs[index] = tab
    end

    container._sectionTabs = tabs
    container._sectionBodies = bodies
    ActivateSection(selectedIndex)

    if panelDef.moduleEnableKey then
        CreateModuleOverlay(container, 0)
        UpdateModuleOverlay(container, ns:GetDBValue(panelDef.moduleEnableKey) == true)
    end
end

local function RenderPanel(container, panelDef, panelKey)
    if panelKey and panelDef.moduleEnableKey and not panelDef.disableSectionLayout then
        RenderSectionedPanel(container, panelDef, panelKey)
    else
        RenderSettingsPanel(container, panelDef)
    end
end

------------------------------------------------------
-- 패널 전환
------------------------------------------------------
local function SetPanelModuleEnabled(panelKey, enabled)
    local panelDef = ns.ConfigTree and ns.ConfigTree.panels and ns.ConfigTree.panels[panelKey]
    if not panelDef or not panelDef.moduleEnableKey then return end

    local oldValue = ns:GetDBValue(panelDef.moduleEnableKey)
    local normalized = enabled == true
    if (oldValue == true) == normalized then
        if settingsPanel and settingsPanel.workspace then
            settingsPanel.workspace:RefreshModuleStates()
        end
        return
    end

    ns:SetDBValue(panelDef.moduleEnableKey, normalized)

    local reloadRequired = true
    for _, setting in ipairs(panelDef.settings or {}) do
        if setting.isModuleToggle then
            if setting.onChange then setting.onChange(normalized) end
            reloadRequired = setting.reloadRequired == true
            break
        end
    end

    local container = panelContainers[panelKey]
    if container and container._moduleOverlay then
        UpdateModuleOverlay(container, normalized)
    end
    if settingsPanel and settingsPanel.workspace then
        settingsPanel.workspace:RefreshModuleStates()
    end
    if reloadRequired then
        StaticPopup_Show("DDINGTOOLKIT_RELOAD_CONFIRM")
    end
end

local function ShowPanel(key)
    if not settingsPanel then return end
    if activePanel and activePanel ~= key then
        StopDetailPreview()
    end
    activePanel = key

    local tree = ns.ConfigTree
    if not tree or not tree.panels[key] then return end
    local panelDef = tree.panels[key]

    if settingsPanel.workspace then
        settingsPanel.workspace:SetPanelMeta(key)
    end
    if settingsPanel.contentScroll then
        local smooth = settingsPanel.contentScroll._smoothController
        if smooth and smooth.Reset then
            smooth:Reset(0)
        else
            settingsPanel.contentScroll:SetVerticalScroll(0)
        end
    end

    -- 모든 컨테이너 숨기기
    for _, c in pairs(panelContainers) do c:Hide() end

    -- 컨테이너 없으면 생성 & 렌더
    if not panelContainers[key] then
        local c = CreateFrame("Frame", nil, settingsPanel.contentChild)
        c:SetPoint("TOPLEFT")
        c:SetPoint("TOPRIGHT")
        panelContainers[key] = c

        if panelDef.customRender then
            -- customRender: 콘텐츠 영역 크기 직접 계산하여 컨테이너에 설정
            local panelW = settingsPanel.contentFrame:GetWidth()
            local panelH = settingsPanel.contentFrame:GetHeight()
            if panelW < 100 then panelW = 920 end
            if panelH < 100 then panelH = 620 end
            local contentW = panelW - 24
            local contentH = panelH - 24
            c:SetSize(contentW, contentH)

            -- customRender + moduleEnableKey: 모듈 활성화 토글 삽입 -- [REFACTOR]
            local customStartY = -S.contentPad
            if panelDef.render then
                panelDef.render(c, key)
            elseif panelDef.moduleEnableKey then
                local isEnabled = ns:GetDBValue(panelDef.moduleEnableKey)
                if isEnabled == nil then isEnabled = true end
                if not settingsPanel.workspace then
                    local hdr = Widgets.CreateSectionHeader(c, ADDON_KEY, L["MODULE_ENABLED"], { isFirst = true })
                    hdr:SetPoint("TOPLEFT", c, "TOPLEFT", S.contentPad, customStartY)
                    hdr:SetPoint("TOPRIGHT", c, "TOPRIGHT", -S.contentPad, customStartY)
                    customStartY = customStartY - hdr:GetHeight()

                    local chk = Widgets.CreateCheckbox(c, ADDON_KEY, L["MODULE_ENABLED"], isEnabled == true, {
                        onChange = function(checked)
                            SetPanelModuleEnabled(key, checked)
                        end,
                    })
                    chk:SetPoint("TOPLEFT", c, "TOPLEFT", S.contentPad, customStartY - S.controlGap)
                    chk:SetPoint("TOPRIGHT", c, "TOPRIGHT", -S.contentPad, customStartY - S.controlGap)
                    customStartY = customStartY - S.controlGap - chk:GetHeight()
                end

                -- 커스텀 컨텐츠용 서브 컨테이너
                local sub = CreateFrame("Frame", nil, c)
                sub:SetPoint("TOPLEFT", c, "TOPLEFT", 0, customStartY)
                sub:SetPoint("BOTTOMRIGHT")
                c._customSubFrame = sub

                -- 오버레이
                CreateModuleOverlay(c, settingsPanel.workspace and 0 or customStartY)
                UpdateModuleOverlay(c, isEnabled == true)

                -- customRender: 모듈에게 서브 컨테이너 위임
                local moduleName = ns.ConfigModuleMap[key]
                local mod = moduleName and ns.modules and ns.modules[moduleName]
                if mod and mod.CreateConfigPanel then
                    mod:CreateConfigPanel(sub)
                end
            else
                -- customRender: 모듈에게 위임
                local moduleName = ns.ConfigModuleMap[key]
                local mod = moduleName and ns.modules and ns.modules[moduleName]
                if mod and mod.CreateConfigPanel then
                    mod:CreateConfigPanel(c)
                else
                    local tf = MakeTextFrame(c,
                        "|cFFAAAA00[" .. (moduleName or key) .. " — custom panel (Phase 5)]|r",
                        C.text.disabled, F.normal)
                    tf:SetPoint("CENTER")
                    c._contentHeight = 100
                    c:SetHeight(100)
                end
            end
        else
            RenderPanel(c, panelDef, key)
        end
    end

    local c = panelContainers[key]
    c:Show()
    if c._refresh then
        c:_refresh()
    end
    settingsPanel.contentChild:SetHeight(c._contentHeight or 600)
end

------------------------------------------------------
-- 패널 갱신 (버튼 onClick 후 재렌더)
------------------------------------------------------
function ConfigUI:RefreshCurrentPanel()
    if not activePanel then return end
    local c = panelContainers[activePanel]
    if not c then return end

    -- Existing frames are reusable; do not allocate another overlay on refresh.
    for _, child in ipairs({ c:GetChildren() }) do child:Hide() end

    -- 재렌더
    local panelDef = ns.ConfigTree and ns.ConfigTree.panels[activePanel]
    if panelDef and not panelDef.customRender then
        RenderPanel(c, panelDef, activePanel)
    end
    settingsPanel.contentChild:SetHeight(c._contentHeight or 600)
end

------------------------------------------------------
-- Search System (CDM-style category search)
------------------------------------------------------
local searchIndex = nil
local searchModeActive = false
local preSearchPanel = nil
local searchDebounceTimer = nil
local searchWidgets = {}
local fullMenuData = nil  -- 트리 필터링용 원본 저장

-- 검색 가능한 위젯 타입
local SEARCHABLE_TYPES = {
            toggle = true, slider = true, dropdown = true, input = true,
    sound = true, font = true, statusbar = true,
    color = true, button = true, separator = true,
}

-- 검색 인덱스 빌드 (panels → flat list)
local function BuildSearchIndex()
    local tree = ns.ConfigTree
    if not tree then return {} end

    local index = {}
    local menuLookup = {}  -- key → 메뉴 텍스트

    -- 메뉴 텍스트 매핑 테이블 (children 재귀 탐색)
    local function buildMenuLookup(items)
        for _, item in ipairs(items) do
            menuLookup[item.key] = item.text
            if item.children then
                buildMenuLookup(item.children)
            end
        end
    end
    buildMenuLookup(tree.menu)

    for key, panelDef in pairs(tree.panels) do
        local panelTitle = menuLookup[key] or panelDef.title or key
        local settings = panelDef.settings
        if settings then
            for _, s in ipairs(settings) do
                if SEARCHABLE_TYPES[s.type] and s.label and s.label ~= "" then
                    index[#index + 1] = {
                        name = s.label,
                        nameLower = s.label:lower(),
                        panelKey = key,
                        panelTitle = panelTitle,
                        type = s.type,
                    }
                end
            end
        end
    end

    return index
end

-- 검색 결과 위젯 정리
local function ClearSearchWidgets()
    for i = #searchWidgets, 1, -1 do
        local w = searchWidgets[i]
        if w then w:Hide(); w:SetParent(nil) end
    end
    wipe(searchWidgets)
end

-- 검색 결과 렌더링
local function RenderSearchResults(contentChild, results)
    ClearSearchWidgets()

    local from = Lib.GetAccent(ADDON_KEY)
    local accentColor = from or { 0.30, 0.85, 0.45 }
    local dimColor = C.text.dim or { 0.45, 0.45, 0.45 }
    local yOffset = 15

    -- 헤더
    local headerFrame = CreateFrame("Frame", nil, contentChild)
    headerFrame:SetPoint("TOPLEFT", contentChild, "TOPLEFT", 10, -yOffset)
    headerFrame:SetPoint("TOPRIGHT", contentChild, "TOPRIGHT", -10, -yOffset)
    headerFrame:SetHeight(28)
    searchWidgets[#searchWidgets + 1] = headerFrame

    local headerText = headerFrame:CreateFontString(nil, "OVERLAY")
    headerText:SetFont(F.path, F.normal, "")
    headerText:SetPoint("TOPLEFT", 0, 0)

    if #results > 0 then
        headerText:SetText("검색 결과  |cff999999(" .. #results .. "개 발견)|r")
    else
        headerText:SetText("|cff999999검색 결과 없음|r")
    end

    -- 밑줄 그라데이션
    local underline = headerFrame:CreateTexture(nil, "ARTWORK")
    underline:SetPoint("TOPLEFT", headerText, "BOTTOMLEFT", 0, -4)
    underline:SetPoint("RIGHT", headerFrame, "RIGHT", 0, 0)
    underline:SetHeight(1)
    underline:SetTexture(SOLID)
    underline:SetGradient("HORIZONTAL",
        CreateColor(accentColor[1], accentColor[2], accentColor[3], 0.6),
        CreateColor(dimColor[1], dimColor[2], dimColor[3], 0.15)
    )

    yOffset = yOffset + 36

    if #results == 0 then
        contentChild:SetHeight(yOffset + 50)
        return
    end

    -- panelKey로 그룹화
    local groups = {}
    local groupOrder = {}
    for _, entry in ipairs(results) do
        if not groups[entry.panelKey] then
            groups[entry.panelKey] = {
                title = entry.panelTitle,
                key = entry.panelKey,
                items = {},
            }
            groupOrder[#groupOrder + 1] = entry.panelKey
        end
        table.insert(groups[entry.panelKey].items, entry)
    end

    -- 각 그룹 렌더링
    for _, panelKey in ipairs(groupOrder) do
        local group = groups[panelKey]

        -- Breadcrumb badge (클릭 → 해당 패널로 이동)
        local badge = CreateFrame("Button", nil, contentChild, "BackdropTemplate")
        badge:SetBackdrop({
            bgFile = SOLID, edgeFile = SOLID, edgeSize = 1,
            insets = { left = 0, right = 0, top = 0, bottom = 0 },
        })
        local widgetBg = C.bg.widget or { 0.14, 0.14, 0.14, 0.9 }
        badge:SetBackdropColor(widgetBg[1], widgetBg[2], widgetBg[3], widgetBg[4] or 0.9)
        badge:SetBackdropBorderColor(0, 0, 0, 1)

        local badgeText = badge:CreateFontString(nil, "OVERLAY")
        badgeText:SetFont(F.path, F.small, "")
        badgeText:SetText(group.title)
        badgeText:SetTextColor(dimColor[1], dimColor[2], dimColor[3], 1)
        badgeText:SetPoint("LEFT", 8, 0)
        badge._text = badgeText

        local textWidth = badgeText:GetStringWidth() or 80
        badge:SetSize(textWidth + 16, 20)
        badge:SetPoint("TOPLEFT", contentChild, "TOPLEFT", 10, -yOffset)
        searchWidgets[#searchWidgets + 1] = badge

        badge:SetScript("OnEnter", function(self)
            self._text:SetTextColor(accentColor[1], accentColor[2], accentColor[3], 1)
            self:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 0.5)
        end)
        badge:SetScript("OnLeave", function(self)
            self._text:SetTextColor(dimColor[1], dimColor[2], dimColor[3], 1)
            self:SetBackdropBorderColor(0, 0, 0, 1)
        end)

        local navKey = group.key
        badge:SetScript("OnClick", function()
            -- 검색 모드 해제
            searchModeActive = false
            preSearchPanel = nil
            -- 검색 박스 비우기
            if settingsPanel and settingsPanel.searchBox then
                settingsPanel.searchBox:SetText("")
                settingsPanel.searchBox.editBox:ClearFocus()
            end
            -- 해당 패널로 이동
            if settingsPanel and settingsPanel.treeMenu then
                settingsPanel.treeMenu:SetSelected(navKey)
            end
            ShowPanel(navKey)
        end)

        yOffset = yOffset + 24

        -- 그룹 내 각 항목
        for _, entry in ipairs(group.items) do
            local itemBtn = CreateFrame("Button", nil, contentChild)
            itemBtn:SetHeight(22)
            itemBtn:SetPoint("TOPLEFT", contentChild, "TOPLEFT", 26, -yOffset)
            itemBtn:SetPoint("TOPRIGHT", contentChild, "TOPRIGHT", -10, -yOffset)
            searchWidgets[#searchWidgets + 1] = itemBtn

            local bullet = itemBtn:CreateFontString(nil, "OVERLAY")
            bullet:SetFont(F.path, F.small, "")
            bullet:SetText("|cff666666\226\128\162|r  " .. entry.name)
            bullet:SetPoint("LEFT", 0, 0)
            bullet:SetJustifyH("LEFT")

            local itemNavKey = entry.panelKey
            itemBtn:SetScript("OnEnter", function()
                bullet:SetTextColor(accentColor[1], accentColor[2], accentColor[3])
            end)
            itemBtn:SetScript("OnLeave", function()
                bullet:SetTextColor(1, 1, 1)
            end)
            itemBtn:SetScript("OnClick", function()
                searchModeActive = false
                preSearchPanel = nil
                if settingsPanel and settingsPanel.searchBox then
                    settingsPanel.searchBox:SetText("")
                    settingsPanel.searchBox.editBox:ClearFocus()
                end
                if settingsPanel and settingsPanel.treeMenu then
                    settingsPanel.treeMenu:SetSelected(itemNavKey)
                end
                ShowPanel(itemNavKey)
            end)

            yOffset = yOffset + 22
        end

        yOffset = yOffset + 8 -- 그룹 간 여백
    end

    contentChild:SetHeight(yOffset + 50)
end

-- 검색 실행
local function PerformSearch(query)
    if not searchIndex then
        searchIndex = BuildSearchIndex()
    end

    local queryLower = query:lower()
    local results = {}

    for _, entry in ipairs(searchIndex) do
        if entry.nameLower:find(queryLower, 1, true)
            or entry.panelTitle:lower():find(queryLower, 1, true) then
            results[#results + 1] = entry
        end
    end

    -- 검색 모드 진입
    if not searchModeActive then
        preSearchPanel = activePanel
        searchModeActive = true
    end

    -- 기존 패널 숨기기
    for _, c in pairs(panelContainers) do c:Hide() end

    -- 검색 결과 렌더링
    if settingsPanel and settingsPanel.contentChild then
        RenderSearchResults(settingsPanel.contentChild, results)
    end
end

-- 검색 해제 (이전 패널 복원)
local function ClearSearchFromToolkit()
    if not searchModeActive then return end
    searchModeActive = false

    ClearSearchWidgets()

    if preSearchPanel then
        ShowPanel(preSearchPanel)
        preSearchPanel = nil
    end
end

-- 트리 메뉴 필터링 (TreeMenu에 Filter() 없으므로 SetMenuData 사용)
-- [REFACTOR] children 계층 구조 지원
local function FilterTreeMenu(searchText)
    if not settingsPanel or not settingsPanel.treeMenu then return end
    if not fullMenuData then return end

    if settingsPanel.workspace then
        settingsPanel.workspace:FilterModules(searchText or "")
        return
    end

    if not searchText or searchText == "" then
        settingsPanel.treeMenu:SetMenuData(fullMenuData)
        return
    end

    local queryLower = searchText:lower()

    -- 항목이 검색어에 매치하는지 확인
    local function ItemMatches(item)
        local text = (item.text or ""):lower()
        if text:find(queryLower, 1, true) then return true end
        local panelDef = ns.ConfigTree and ns.ConfigTree.panels[item.key]
        if panelDef and panelDef.settings then
            for _, s in ipairs(panelDef.settings) do
                if s.label and s.label:lower():find(queryLower, 1, true) then
                    return true
                end
            end
        end
        return false
    end

    -- 재귀 필터링
    local function FilterItems(items)
        local result = {}
        for _, item in ipairs(items) do
            if item.children then
                local filteredChildren = FilterItems(item.children)
                if #filteredChildren > 0 or ItemMatches(item) then
                    result[#result + 1] = {
                        text = item.text, key = item.key,
                        children = #filteredChildren > 0 and filteredChildren or item.children,
                    }
                end
            else
                if ItemMatches(item) then
                    result[#result + 1] = { text = item.text, key = item.key }
                end
            end
        end
        return result
    end

    local filtered = FilterItems(fullMenuData)
    settingsPanel.treeMenu:SetMenuData(filtered, true)
end

------------------------------------------------------
-- 초기화
------------------------------------------------------
function ConfigUI:Initialize()
    if settingsPanel then return settingsPanel end

    -- ConfigTree 초기화
    ns:InitConfigTree()

    -- StyleLib 애드온 등록
    if not Lib.IsRegistered(ADDON_KEY) then
        Lib.RegisterAddon(ADDON_KEY)
    end

    -- 메인 패널
    local version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "1.0" -- [12.0.1] GetAddOnMetadata 폴백 제거

    if ns.ToolkitWorkspace and ns.ToolkitWorkspace.Create then
        settingsPanel = ns.ToolkitWorkspace:Create("DDingUI Toolkit", version, {
            width = 1180,
            height = 720,
            minWidth = 930,
            minHeight = 580,
            onSelect = function(key)
                if settingsPanel and settingsPanel.searchBox
                    and settingsPanel.searchBox:GetText() ~= ""
                then
                    settingsPanel.searchBox:SetText("")
                end
                ShowPanel(key)
            end,
            onModuleToggle = function(key, enabled)
                SetPanelModuleEnabled(key, enabled)
            end,
        })
    else
        settingsPanel = Lib.CreateSettingsPanel(ADDON_KEY, "DDingUI Toolkit", version, {
            width = 920, height = 620, menuWidth = 200,
        })
    end
    if settingsPanel.titleBar then
        if settingsPanel.titleBar.titleText then
            settingsPanel.titleBar.titleText:SetText("")
            settingsPanel.titleBar.titleText:Hide()
        end
        if not settingsPanel.titleBar.brandLogo then
            settingsPanel.titleBar.brandLogo = settingsPanel.titleBar:CreateTexture(nil, "ARTWORK")
        end
        settingsPanel.titleBar.brandLogo:ClearAllPoints()
        settingsPanel.titleBar.brandLogo:SetPoint("LEFT", settingsPanel.titleBar, "LEFT", 10, 0)
        settingsPanel.titleBar.brandLogo:SetSize(144, 36)
        settingsPanel.titleBar.brandLogo:SetTexture("Interface\\AddOns\\DDingUI_Toolkit\\Media\\logo_wordmark.tga")
        settingsPanel.titleBar.brandLogo:SetTexCoord(0, 1, 0, 1)
        settingsPanel.titleBar.brandLogo:Show()
        if settingsPanel.titleBar.verText then
            settingsPanel.titleBar.verText:ClearAllPoints()
            settingsPanel.titleBar.verText:SetPoint("LEFT", settingsPanel.titleBar.brandLogo, "RIGHT", 5, -1)
        end
    end
    EnableRightClickMouselook(settingsPanel.frame)
    EnableRightClickMouselook(settingsPanel.titleBar)
    EnableRightClickMouselook(settingsPanel.treeFrame)
    EnableRightClickMouselook(settingsPanel.contentFrame)
    EnableRightClickMouselook(settingsPanel.contentScroll)

    -- 트리 메뉴
    local tree = ns.ConfigTree
    local from = Lib.GetAccent(ADDON_KEY)
    local treeMenu = settingsPanel.treeMenu
    if not treeMenu then
        treeMenu = Lib.CreateTreeMenu(settingsPanel.treeFrame, ADDON_KEY, tree.menu, {
            defaultKey = "general",
            selectedColor = { from[1], from[2], from[3], 0.3 },
            onSelect = function(key) ShowPanel(key) end,
        })
    end
    settingsPanel.treeMenu = treeMenu

    -- 원본 메뉴 데이터 저장 (검색 필터 해제 시 복원용)
    fullMenuData = tree.menu

    -- 검색 박스 (타이틀바 우측, 닫기 버튼 좌측)
    local searchBox = Widgets.CreateSearchBox(settingsPanel.titleBar, 200)
    searchBox:SetPoint("RIGHT", settingsPanel.titleBar.closeBtn, "LEFT", -10, 0)
    settingsPanel.searchBox = searchBox

    local editModeButton = Widgets.CreateButton(
        settingsPanel.titleBar,
        ADDON_KEY,
        LT("EDIT_MODE", "Edit Mode"),
        function()
            settingsPanel.frame:Hide()
            C_Timer.After(0, function()
                if ns.ToolkitMovers and ns.ToolkitMovers.ToggleConfigMode then
                    ns.ToolkitMovers:ToggleConfigMode()
                end
            end)
        end,
        {
            width = 104,
            height = 24,
            tooltip = LT("EDIT_MODE_DESC", "Move and align Toolkit frames."),
        }
    )
    editModeButton:SetPoint("RIGHT", searchBox, "LEFT", -8, 0)
    settingsPanel.editModeButton = editModeButton

    local function RefreshEditModeButton(active)
        if not editModeButton or not editModeButton.label then return end
        editModeButton.label:SetText(active and LT("EDIT_MODE_ACTIVE", "Editing") or LT("EDIT_MODE", "Edit Mode"))
        editModeButton:SetAlpha(active and 1 or 0.92)
    end
    if ns.ToolkitMovers and ns.ToolkitMovers.RegisterStateCallback then
        ns.ToolkitMovers:RegisterStateCallback(RefreshEditModeButton)
    end

    -- 검색 박스 연결: 트리 필터 + 콘텐츠 검색
    searchBox:SetOnTextChanged(function(text)
        FilterTreeMenu(text)

        -- 디바운스 타이머 취소
        if searchDebounceTimer then
            searchDebounceTimer:Cancel()
            searchDebounceTimer = nil
        end

        if text and text ~= "" then
            -- 0.2초 디바운스 후 콘텐츠 검색
            searchDebounceTimer = C_Timer.NewTimer(0.2, function()
                PerformSearch(text)
            end)
        else
            ClearSearchFromToolkit()
        end
    end)

    -- OnShow → 활성 패널 표시
    settingsPanel.frame:HookScript("OnShow", function()
        local key = treeMenu:GetSelected() or (settingsPanel.workspace and "overview" or "general")
        RefreshEditModeButton(ns.ToolkitMovers and ns.ToolkitMovers:IsActive())
        ShowPanel(key)
    end)
    settingsPanel.frame:HookScript("OnHide", function()
        StopDetailPreview()
        if Widgets.CloseDropdowns then
            Widgets.CloseDropdowns()
        end
        if searchDebounceTimer then
            searchDebounceTimer:Cancel()
            searchDebounceTimer = nil
        end
        searchModeActive = false
        preSearchPanel = nil
        ClearSearchWidgets()
        if searchBox:GetText() ~= "" then
            searchBox:SetText("")
        end
        searchBox.editBox:ClearFocus()
    end)

    return settingsPanel
end

------------------------------------------------------
-- Public API
------------------------------------------------------
function ConfigUI:Show()
    if ns.ToolkitMovers and ns.ToolkitMovers.IsActive and ns.ToolkitMovers:IsActive() then
        ns.ToolkitMovers:ToggleConfigMode()
    end
    local p = self:Initialize()
    if p then
        if p.frame.ShowAnimated then
            p.frame:ShowAnimated()
        else
            p.frame:Show()
        end
    end
end

function ConfigUI:Hide()
    if settingsPanel then
        if settingsPanel.frame.HideAnimated then
            settingsPanel.frame:HideAnimated()
        else
            settingsPanel.frame:Hide()
        end
    end
end

function ConfigUI:Toggle()
    if settingsPanel and settingsPanel.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

function ConfigUI:SelectPanel(key)
    self:Show()
    if settingsPanel and settingsPanel.treeMenu then
        settingsPanel.treeMenu:SetSelected(key)
        ShowPanel(key)
    end
end

function ConfigUI:GetFrame()
    if settingsPanel then return settingsPanel.frame end
    return nil
end

function ConfigUI:IsShown()
    return settingsPanel and settingsPanel.frame:IsShown() or false
end

function ConfigUI:SelectModule(moduleName)
    for key, name in pairs(ns.ConfigModuleMap) do
        if name == moduleName then
            self:SelectPanel(key)
            return
        end
    end
end
