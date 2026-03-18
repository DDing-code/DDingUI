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
    fs:SetPoint("RIGHT")
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
    container:SetSize(500, 72)

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
    local dropdown = Lib.CreateDropdown(container, ADDON_KEY, setting.label or "", options, current, {
        width = 200,
        onChange = function(value)
            ns:SetDBValue(setting.key, value)
            if value and value ~= "" then PlaySoundFile(value, "Master") end
            if setting.onChange then setting.onChange(value) end
        end,
    })
    dropdown:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)

    -- 2) 커스텀 경로 EditBox -- [12.0.1]
    local customKey = setting.customPathKey
    if customKey then
        local customLabel = container:CreateFontString(nil, "OVERLAY")
        customLabel:SetFont(F.path, F.small, "")
        customLabel:SetTextColor(u(C.text.dim))
        customLabel:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -28)
        customLabel:SetText(L and L["SOUND_CUSTOM_PATH"] or "커스텀 경로 (mp3/ogg/wav)")

        local editBox = CreateFrame("EditBox", nil, container, "BackdropTemplate")
        editBox:SetSize(280, 22)
        editBox:SetPoint("TOPLEFT", customLabel, "BOTTOMLEFT", 0, -3)
        editBox:SetBackdrop({
            bgFile = SOLID, edgeFile = SOLID, edgeSize = 1,
            insets = { left = 4, right = 4, top = 2, bottom = 2 },
        })
        local inputBg = C.bg.input or { 0.08, 0.08, 0.08, 0.9 }
        editBox:SetBackdropColor(inputBg[1], inputBg[2], inputBg[3], inputBg[4] or 0.9)
        editBox:SetBackdropBorderColor(u(C.border.default))
        editBox:SetFont(F.path, F.small, "")
        editBox:SetTextColor(u(C.text.normal))
        editBox:SetAutoFocus(false)
        editBox:SetMaxLetters(256)
        editBox:SetText(ns:GetDBValue(customKey) or "")

        editBox:SetScript("OnEnterPressed", function(self)
            local val = self:GetText()
            ns:SetDBValue(customKey, val)
            self:ClearFocus()
        end)
        editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

        -- 테스트 버튼 -- [12.0.1]
        local testBtn = Lib.CreateButton(container, ADDON_KEY, L and L["SOUND_TEST"] or "테스트", function()
            local customPath = ns:GetDBValue(customKey)
            local soundFile = ns:GetDBValue(setting.key)
            -- 현재 채널 키 추출 (soundFile → soundChannel 패턴)
            local channelKey = setting.key:gsub("soundFile$", "soundChannel")
            local channel = ns:GetDBValue(channelKey) or "Master"
            ns:PlaySound(soundFile, channel, customPath)
        end, { width = 70 })
        testBtn:SetPoint("LEFT", editBox, "RIGHT", 6, 0)

        container:SetHeight(72)
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
    return Lib.CreateDropdown(parent, ADDON_KEY, setting.label or "", options, current, {
        width = 200,
        onChange = function(value)
            ns:SetDBValue(setting.key, value)
            if setting.onChange then setting.onChange(value) end
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
    return Lib.CreateDropdown(parent, ADDON_KEY, setting.label or "", options, current, {
        width = 200,
        onChange = function(value)
            ns:SetDBValue(setting.key, value)
            if setting.onChange then setting.onChange(value) end
        end,
    })
end

------------------------------------------------------
-- 위젯: Color 버튼
------------------------------------------------------
local function CreateColorButton(parent, setting)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(280, 22)

    local label = container:CreateFontString(nil, "OVERLAY")
    label:SetFont(F.path, F.normal, "")
    label:SetTextColor(u(C.text.normal))
    label:SetPoint("LEFT", 0, 0)
    label:SetText(setting.label or "")

    local swatch = CreateFrame("Button", nil, container, "BackdropTemplate")
    swatch:SetSize(22, 14)
    swatch:SetPoint("LEFT", label, "RIGHT", S.labelGap, 0)
    swatch:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1 })
    swatch:SetBackdropBorderColor(u(C.border.default))

    local function ReadColor()
        local c = ns:GetDBValue(setting.key)
        if not c then return 1, 1, 1, 1 end
        if setting.colorFormat == "rgb_object" then
            return c.r or 1, c.g or 1, c.b or 1, 1
        end
        return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
    end

    local function UpdateSwatch()
        local r, g, b = ReadColor()
        swatch:SetBackdropColor(r, g, b, 1)
    end
    UpdateSwatch()

    local function SaveColor(r, g, b, a)
        if setting.colorFormat == "rgb_object" then
            ns:SetDBValue(setting.key, { r = r, g = g, b = b })
        elseif setting.hasAlpha then
            ns:SetDBValue(setting.key, { r, g, b, a })
        else
            ns:SetDBValue(setting.key, { r, g, b })
        end
        UpdateSwatch()
        if setting.onChange then setting.onChange(ns:GetDBValue(setting.key)) end
    end

    swatch:SetScript("OnClick", function()
        local r, g, b, a = ReadColor()
        local prevColor = ns:GetDBValue(setting.key)

        local function OnChanged()
            local nr, ng, nb = ColorPickerFrame:GetColorRGB()
            local na = a
            if setting.hasAlpha then
                if ColorPickerFrame.GetColorAlpha then
                    na = ColorPickerFrame:GetColorAlpha()
                elseif OpacitySliderFrame then
                    na = 1 - OpacitySliderFrame:GetValue()
                end
            end
            SaveColor(nr, ng, nb, na)
        end

        -- Retail 10.2.5+ API
        if ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:SetupColorPickerAndShow({
                r = r, g = g, b = b,
                opacity = setting.hasAlpha and (1 - a) or nil,
                hasOpacity = setting.hasAlpha or false,
                swatchFunc = OnChanged,
                opacityFunc = setting.hasAlpha and OnChanged or nil,
                cancelFunc = function()
                    ns:SetDBValue(setting.key, prevColor)
                    UpdateSwatch()
                end,
            })
        else
            ColorPickerFrame:SetColorRGB(r, g, b)
            ColorPickerFrame.hasOpacity = setting.hasAlpha
            ColorPickerFrame.opacity = setting.hasAlpha and (1 - a) or nil
            ColorPickerFrame.func = OnChanged
            ColorPickerFrame.opacityFunc = setting.hasAlpha and OnChanged or nil
            ColorPickerFrame.cancelFunc = function()
                ns:SetDBValue(setting.key, prevColor)
                UpdateSwatch()
            end
            ColorPickerFrame:Hide(); ColorPickerFrame:Show()
        end
    end)

    -- hover
    swatch:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(u(C.border.active))
    end)
    swatch:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(u(C.border.default))
    end)

    container.swatch = swatch
    container.Refresh = UpdateSwatch
    return container
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
        container._moduleOverlay:SetPoint("TOPLEFT", container, "TOPLEFT", 0, yStart)
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
    local tex = overlay:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetColorTexture(0, 0, 0, 0.45)
    container._moduleOverlay = overlay
    return overlay
end

------------------------------------------------------
-- 패널 렌더러
------------------------------------------------------
local function RenderPanel(container, panelDef)
    local yOff = -S.contentPad
    local pad  = S.contentPad
    local moduleToggleEndY = nil  -- 모듈 활성화 토글 아래 Y 오프셋 추적

    -- 설명 텍스트
    if panelDef.desc then
        local df = MakeTextFrame(container, panelDef.desc, C.text.dim, F.small)
        df:SetPoint("TOPLEFT", container, "TOPLEFT", pad, yOff)
        df:SetPoint("RIGHT", container, "RIGHT", -pad, 0)
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

        -- header -----------------------------------------------
        if s.type == "header" then
            w = Lib.CreateSectionHeader(container, ADDON_KEY, s.label, { isFirst = s.isFirst })
            w:SetPoint("TOPLEFT", container, "TOPLEFT", pad, yOff)
            w:SetPoint("RIGHT", container, "RIGHT", -pad, 0)
            yOff = yOff - w:GetHeight()

        -- separator --------------------------------------------
        elseif s.type == "separator" then
            local sep = Lib.CreateSeparator(container)
            sep:SetPoint("TOPLEFT", container, "TOPLEFT", pad, yOff - S.controlGap)
            sep:SetPoint("RIGHT", container, "RIGHT", -pad, 0)
            yOff = yOff - S.controlGap * 2 - 1

        -- text (정적 텍스트) -----------------------------------
        elseif s.type == "text" then
            local tf = MakeTextFrame(container, s.label, C.text.dim, F.small)
            tf:SetPoint("TOPLEFT", container, "TOPLEFT", pad, yOff - S.controlGap)
            tf:SetPoint("RIGHT", container, "RIGHT", -pad, 0)
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
                onChangeFn = function(checked) SetValue(s, checked) end
            end
            w = Lib.CreateCheckbox(container, ADDON_KEY, s.label or "", val, {
                onChange = onChangeFn,
            })
            w:SetPoint("TOPLEFT", container, "TOPLEFT", pad, yOff - S.controlGap)
            yOff = yOff - S.controlGap - 20
            -- 모듈 토글 위치 추적 -- [REFACTOR]
            if s.isModuleToggle and panelDef.moduleEnableKey then
                moduleToggleEndY = yOff
            end

        -- slider -----------------------------------------------
        elseif s.type == "slider" then
            local val = ns:GetDBValue(s.key) or s.min
            w = Lib.CreateSlider(container, ADDON_KEY, s.label or "",
                s.min, s.max, s.step, val, {
                    width = 300,
                    onChange = function(value)
                        ns:SetDBValue(s.key, value)
                        if s.onChange then s.onChange(value) end
                    end,
                })
            w:SetPoint("TOPLEFT", container, "TOPLEFT", pad, yOff - S.controlGap)
            yOff = yOff - S.controlGap - 52

        -- dropdown ---------------------------------------------
        elseif s.type == "dropdown" then
            local opts = ResolveOptions(s.options)
            local val  = ns:GetDBValue(s.key)
            w = Lib.CreateDropdown(container, ADDON_KEY, s.label or "", opts, val, {
                width = 160,
                onChange = function(value)
                    ns:SetDBValue(s.key, value)
                    if s.onChange then s.onChange(value) end
                end,
            })
            w:SetPoint("TOPLEFT", container, "TOPLEFT", pad, yOff - S.controlGap)
            yOff = yOff - S.controlGap - 24

        -- button -----------------------------------------------
        elseif s.type == "button" then
            w = Lib.CreateButton(container, ADDON_KEY, s.label or "", function(self)
                if s.onClick then s.onClick() end
                -- refreshPanel 플래그: 버튼 클릭 후 패널 갱신
                if s.refreshPanel and activePanel then
                    ConfigUI:RefreshCurrentPanel()
                end
            end, { width = s.width or 160 })
            w:SetPoint("TOPLEFT", container, "TOPLEFT", pad, yOff - S.controlGap)
            yOff = yOff - S.controlGap - 24

        -- color ------------------------------------------------
        elseif s.type == "color" then
            w = CreateColorButton(container, s)
            w:SetPoint("TOPLEFT", container, "TOPLEFT", pad, yOff - S.controlGap)
            yOff = yOff - S.controlGap - 22

        -- sound (LSM + 커스텀 경로) -- [12.0.1] -----------------
        elseif s.type == "sound" then
            w = CreateSoundDropdown(container, s)
            w:SetPoint("TOPLEFT", container, "TOPLEFT", pad, yOff - S.controlGap)
            local soundHeight = s.customPathKey and 72 or 24
            yOff = yOff - S.controlGap - soundHeight

        -- font (LSM) -------------------------------------------
        elseif s.type == "font" then
            w = CreateFontDropdown(container, s)
            w:SetPoint("TOPLEFT", container, "TOPLEFT", pad, yOff - S.controlGap)
            yOff = yOff - S.controlGap - 24

        -- statusbar (LSM) --------------------------------------
        elseif s.type == "statusbar" then
            w = CreateStatusBarDropdown(container, s)
            w:SetPoint("TOPLEFT", container, "TOPLEFT", pad, yOff - S.controlGap)
            yOff = yOff - S.controlGap - 24

        -- custom: colorArray (CursorTrail 색상 그리드) -----------
        elseif s.type == "custom" and s.customType == "colorArray" then
            local maxColors = s.maxColors or 10
            local colsPerRow = 2
            local btnW, btnH, btnGap = 140, 22, 6
            local gridFrame = CreateFrame("Frame", nil, container)
            gridFrame:SetSize(colsPerRow * (btnW + btnGap), math.ceil(maxColors / colsPerRow) * (btnH + btnGap))
            gridFrame:SetPoint("TOPLEFT", container, "TOPLEFT", pad, yOff - S.controlGap)

            for i = 1, maxColors do
                local row = math.ceil(i / colsPerRow) - 1
                local col = (i - 1) % colsPerRow
                local colorSetting = {
                    key = s.colorsKey .. "." .. i,
                    label = string.format(L["CURSORTRAIL_COLOR_N"] or "Color %d", i),
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
            w = Lib.CreateDropdown(container, ADDON_KEY, L["PRESET"] or "Preset", presetList, val, {
                width = 200,
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
            yOff = yOff - S.controlGap - 24

        -- custom: 기타 미구현 ----------------------------------
        elseif s.type == "custom" then
            local cf = MakeTextFrame(container,
                "|cFF666666[Custom: " .. (s.customType or "?") .. "]|r",
                C.text.disabled, F.small)
            cf:SetPoint("TOPLEFT", container, "TOPLEFT", pad, yOff - S.controlGap)
            cf:SetPoint("RIGHT", container, "RIGHT", -pad, 0)
            yOff = yOff - S.controlGap - 20
        end
    end

    -- 컨테이너 높이 저장
    container._contentHeight = math.abs(yOff) + pad
    container:SetHeight(container._contentHeight)

    -- 모듈 비활성화 오버레이 생성 -- [REFACTOR]
    if panelDef.moduleEnableKey and moduleToggleEndY then
        CreateModuleOverlay(container, moduleToggleEndY)
        local isEnabled = ns:GetDBValue(panelDef.moduleEnableKey)
        UpdateModuleOverlay(container, isEnabled ~= false)
    end
end

------------------------------------------------------
-- 패널 전환
------------------------------------------------------
local function ShowPanel(key)
    if not settingsPanel then return end
    activePanel = key

    local tree = ns.ConfigTree
    if not tree or not tree.panels[key] then return end

    -- 모든 컨테이너 숨기기
    for _, c in pairs(panelContainers) do c:Hide() end

    -- 컨테이너 없으면 생성 & 렌더
    if not panelContainers[key] then
        local c = CreateFrame("Frame", nil, settingsPanel.contentChild)
        c:SetPoint("TOPLEFT")
        c:SetPoint("RIGHT")
        panelContainers[key] = c

        local panelDef = tree.panels[key]

        if panelDef.customRender then
            -- customRender: 콘텐츠 영역 크기 직접 계산하여 컨테이너에 설정
            local panelW = settingsPanel.frame:GetWidth()
            local panelH = settingsPanel.frame:GetHeight()
            if panelW < 100 then panelW = 920 end
            if panelH < 100 then panelH = 620 end
            local menuW = 200
            local contentW = panelW - menuW - 30
            local contentH = panelH - 60
            c:SetSize(contentW, contentH)

            -- customRender + moduleEnableKey: 모듈 활성화 토글 삽입 -- [REFACTOR]
            local customStartY = -S.contentPad
            if panelDef.moduleEnableKey then
                local hdr = Lib.CreateSectionHeader(c, ADDON_KEY, L["MODULE_ENABLED"], { isFirst = true })
                hdr:SetPoint("TOPLEFT", c, "TOPLEFT", S.contentPad, customStartY)
                hdr:SetPoint("RIGHT", c, "RIGHT", -S.contentPad, 0)
                customStartY = customStartY - hdr:GetHeight()

                local isEnabled = ns:GetDBValue(panelDef.moduleEnableKey)
                if isEnabled == nil then isEnabled = true end
                local chk = Lib.CreateCheckbox(c, ADDON_KEY, L["MODULE_ENABLED"], isEnabled ~= false, {
                    onChange = function(checked)
                        ns:SetDBValue(panelDef.moduleEnableKey, checked)
                        UpdateModuleOverlay(c, checked)
                        StaticPopup_Show("DDINGTOOLKIT_RELOAD_CONFIRM")
                    end,
                })
                chk:SetPoint("TOPLEFT", c, "TOPLEFT", S.contentPad, customStartY - S.controlGap)
                customStartY = customStartY - S.controlGap - 20

                -- 커스텀 컨텐츠용 서브 컨테이너
                local sub = CreateFrame("Frame", nil, c)
                sub:SetPoint("TOPLEFT", c, "TOPLEFT", 0, customStartY)
                sub:SetPoint("BOTTOMRIGHT")
                c._customSubFrame = sub

                -- 오버레이
                CreateModuleOverlay(c, customStartY)
                UpdateModuleOverlay(c, isEnabled ~= false)

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
            RenderPanel(c, panelDef)
        end
    end

    local c = panelContainers[key]
    c:Show()
    settingsPanel.contentChild:SetHeight(c._contentHeight or 600)
end

------------------------------------------------------
-- 패널 갱신 (버튼 onClick 후 재렌더)
------------------------------------------------------
function ConfigUI:RefreshCurrentPanel()
    if not activePanel then return end
    local c = panelContainers[activePanel]
    if not c then return end

    -- 오버레이 참조 보존 후 자식 숨기기 -- [REFACTOR]
    local savedOverlay = c._moduleOverlay
    c._moduleOverlay = nil
    for _, child in ipairs({ c:GetChildren() }) do child:Hide() end

    -- 재렌더
    local panelDef = ns.ConfigTree and ns.ConfigTree.panels[activePanel]
    if panelDef and not panelDef.customRender then
        RenderPanel(c, panelDef)
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
    toggle = true, slider = true, dropdown = true,
    sound = true, font = true, statusbar = true,
    color = true, button = true, separator = true,
}

-- 검색 인덱스 빌드 (panels → flat list)
local function BuildSearchIndex()
    local tree = ns.ConfigTree
    if not tree then return {} end

    local index = {}
    local menuLookup = {}  -- key → 메뉴 텍스트

    -- 메뉴 텍스트 매핑 테이블
    for _, item in ipairs(tree.menu) do
        menuLookup[item.key] = item.text
    end

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
    headerFrame:SetPoint("RIGHT", contentChild, "RIGHT", -10, 0)
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
            itemBtn:SetPoint("RIGHT", contentChild, "RIGHT", -10, 0)
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
local function FilterTreeMenu(searchText)
    if not settingsPanel or not settingsPanel.treeMenu then return end
    if not fullMenuData then return end

    if not searchText or searchText == "" then
        settingsPanel.treeMenu:SetMenuData(fullMenuData)
        return
    end

    local queryLower = searchText:lower()
    local filtered = {}

    for _, item in ipairs(fullMenuData) do
        local text = (item.text or ""):lower()
        local panelDef = ns.ConfigTree and ns.ConfigTree.panels[item.key]
        local contentMatch = false

        -- 설정 항목 내 검색
        if panelDef and panelDef.settings then
            for _, s in ipairs(panelDef.settings) do
                if s.label and s.label:lower():find(queryLower, 1, true) then
                    contentMatch = true
                    break
                end
            end
        end

        if text:find(queryLower, 1, true) or contentMatch then
            filtered[#filtered + 1] = { text = item.text, key = item.key }
        end
    end

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

    settingsPanel = Lib.CreateSettingsPanel(ADDON_KEY, "DDingUI Toolkit", version, {
        width = 920, height = 620, menuWidth = 200,
    })

    -- 트리 메뉴
    local tree = ns.ConfigTree
    local from = Lib.GetAccent(ADDON_KEY)
    local treeMenu = Lib.CreateTreeMenu(settingsPanel.treeFrame, ADDON_KEY, tree.menu, {
        defaultKey = "general",
        selectedColor = { from[1], from[2], from[3], 0.3 },
        onSelect = function(key) ShowPanel(key) end,
    })
    settingsPanel.treeMenu = treeMenu

    -- 원본 메뉴 데이터 저장 (검색 필터 해제 시 복원용)
    fullMenuData = tree.menu

    -- 검색 박스 (타이틀바 우측, 닫기 버튼 좌측)
    local searchBox = Lib.CreateSearchBox(settingsPanel.titleBar, 200)
    searchBox:SetPoint("RIGHT", settingsPanel.titleBar.closeBtn, "LEFT", -10, 0)
    settingsPanel.searchBox = searchBox

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
        local key = treeMenu:GetSelected() or "general"
        ShowPanel(key)
    end)

    return settingsPanel
end

------------------------------------------------------
-- Public API
------------------------------------------------------
function ConfigUI:Show()
    local p = self:Initialize()
    if p then p.frame:Show() end
end

function ConfigUI:Hide()
    if settingsPanel then settingsPanel.frame:Hide() end
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
