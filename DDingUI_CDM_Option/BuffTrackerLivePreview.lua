local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
local L = LibStub("AceLocale-3.0"):GetLocale("DDingUI")
local GUI = DDingUI.GUI
local SL = _G.DDingUI_StyleLib
local FLAT = (SL and SL.Textures and SL.Textures.flat) or "Interface\\Buttons\\WHITE8x8"
local THEME = GUI.THEME

-- [REFACTOR] Custom aura live preview = display copy of the real runtime tracker frame.
-- The old card re-drew bars/icons/rings/texts with its own sizes, fonts, sample values and
-- colours, so it never matched the game. Now it copies the frame BuffTrackerBar actually drew
-- (DashboardPreview.PaintFit: textures, texts, cooldowns, status bars) at its real size.
-- When the tracker is not on screen, the card offers the runtime preview mode
-- (ResourceBars:EnablePreviewMode — sample values drawn by the runtime itself).
local Preview = {}
GUI.BuffTrackerLivePreview = Preview

local function T(key, fallback)
    return rawget(L, key) or fallback or key
end

local function FontPath()
    return DDingUI.GetGlobalFont and DDingUI:GetGlobalFont() or STANDARD_TEXT_FONT
end

local function CreateText(parent, color, justify)
    local text = parent:CreateFontString(nil, "OVERLAY")
    text:SetFont(FontPath(), 12, "") -- [STYLE] settings text >= 12pt
    text:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    text:SetJustifyH(justify or "LEFT")
    return text
end

local VISUAL_TYPES = { bar = true, ring = true, icon = true, text = true }

local function PreviewModeEnabled()
    return DDingUI.IsBuffTrackerPreviewEnabled and DDingUI:IsBuffTrackerPreviewEnabled() or false
end

-- Runtime frame lists are indexed like the runtime config list (GetTrackedBuffConfigs).
local function RuntimeIndex(entry, trackedBuffs)
    local configs = DDingUI.GetTrackedBuffConfigs and DDingUI:GetTrackedBuffConfigs() or trackedBuffs or {}
    for index, candidate in ipairs(configs) do
        if candidate == entry or (entry.uid and candidate.uid == entry.uid) then return index, configs end
    end
end

local function RuntimeFrame(index, displayType)
    if not index then return nil end
    if displayType == "bar" or displayType == "ring" then
        local bars = DDingUI.GetTrackedBuffBars and DDingUI:GetTrackedBuffBars()
        return bars and bars[index]
    elseif displayType == "icon" then
        local icons = DDingUI.GetTrackedBuffIcons and DDingUI:GetTrackedBuffIcons()
        return icons and icons[index]
    elseif displayType == "text" then
        local texts = DDingUI.GetTrackedBuffTexts and DDingUI:GetTrackedBuffTexts()
        return texts and texts[index]
    end
end

--- Visible runtime frames for the selected tracker (a group copies its children).
local function CollectSources(entry, trackedBuffs)
    local reader = GUI.DashboardPreview
    local sources, expected = {}, 0
    local function Add(child)
        if type(child) ~= "table" or child.disabled then return end
        local displayType = child.displayType or "bar"
        if not VISUAL_TYPES[displayType] then return end
        expected = expected + 1
        local frame = RuntimeFrame(RuntimeIndex(child, trackedBuffs), displayType)
        if frame and reader and reader.Read(frame, "IsVisible") == true then
            sources[#sources + 1] = frame
        end
    end
    if entry.isGroup then
        for _, childIndex in ipairs(entry.controlledChildren or {}) do
            Add(trackedBuffs and trackedBuffs[childIndex])
        end
    else
        Add(entry)
    end
    return sources, expected
end

local function RingColor(entry)
    local settings = entry and entry.settings
    return settings and settings.ringColor or { 1, 0.8, 0, 1 } -- BuffTrackerBar ring default
end

local function AppendFingerprint(parts, value, depth, seen)
    local valueType = type(value)
    if valueType ~= "table" then
        parts[#parts + 1] = valueType .. "=" .. tostring(value)
        return
    end
    if depth <= 0 or seen[value] then
        parts[#parts + 1] = "table"
        return
    end
    seen[value] = true
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do
        parts[#parts + 1] = tostring(key)
        AppendFingerprint(parts, value[key], depth - 1, seen)
    end
    seen[value] = nil
end

function Preview:GetSignature(entry, trackedBuffs)
    local parts = {}
    AppendFingerprint(parts, entry, 4, {})
    if entry and entry.isGroup and trackedBuffs then
        for _, childIndex in ipairs(entry.controlledChildren or {}) do
            AppendFingerprint(parts, trackedBuffs[childIndex], 2, {})
        end
    end
    return table.concat(parts, "|")
end

function Preview:Create(parent)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetHeight(126)
    frame:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    frame:SetBackdropColor(THEME.bgDark[1], THEME.bgDark[2], THEME.bgDark[3], 0.96)
    frame:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 0.72)
    local base = DDingUI.GUIBase
    if base and base.RoundFrame then -- [STYLE] StyleLib 1.3 card
        base.RoundFrame(frame, base.RADIUS and base.RADIUS.card or 10)
    end
    frame.live = true -- BuffTrackerGUI repaints live copies on its timer

    local title = CreateText(frame, THEME.textDim)
    title:SetPoint("TOPLEFT", 12, -9)
    title:SetText(L["Live Preview"] or "Live Preview")
    local name = CreateText(frame, THEME.textBright)
    name:SetPoint("LEFT", title, "RIGHT", 8, 0)
    name:SetPoint("RIGHT", frame, "RIGHT", -150, 0)
    name:SetWordWrap(false)
    local mode = CreateText(frame, THEME.accent, "RIGHT")
    mode:SetPoint("TOPRIGHT", -12, -9)

    -- The copy surface stands for the game screen: square, like the real frames.
    local canvas = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    canvas:SetPoint("TOPLEFT", 10, -30)
    canvas:SetPoint("BOTTOMRIGHT", -10, 8)
    canvas:SetBackdrop({ bgFile = FLAT })
    canvas:SetBackdropColor(THEME.input[1], THEME.input[2], THEME.input[3], 0.9)
    if canvas.SetClipsChildren then canvas:SetClipsChildren(true) end
    local host = CreateFrame("Frame", nil, canvas)
    host:SetAllPoints(canvas)
    host:EnableMouse(false)

    local hint = CreateText(canvas, THEME.textDim, "CENTER")
    hint:SetPoint("LEFT", canvas, "LEFT", 12, 8)
    hint:SetPoint("RIGHT", canvas, "RIGHT", -12, 8)
    hint:SetWordWrap(true)

    local toggle
    if GUI.CreateStyledButton then
        toggle = GUI.CreateStyledButton(canvas, T("Show on screen", "화면 미리보기 켜기"), 150, 24)
        toggle:SetPoint("TOP", hint, "BOTTOM", 0, -8)
        toggle:SetScript("OnClick", function()
            -- runtime preview relayouts tracker containers: out of combat only
            if not DDingUI.ToggleBuffTrackerPreview or InCombatLockdown() then return end
            DDingUI:ToggleBuffTrackerPreview()
            if type(frame.onPreviewModeChanged) == "function" then frame.onPreviewModeChanged() end
            frame:Refresh(frame._entry, frame._trackedBuffs)
        end)
        toggle:Hide()
    end

    frame.canvas, frame.host, frame.hint, frame.toggle = canvas, host, hint, toggle
    frame.title, frame.name, frame.mode = title, name, mode

    function frame:StopMotion()
        local visuals = DDingUI.RestrictedAuraVisuals
        if visuals and visuals.StopTextMotion then visuals:StopTextMotion(self.host) end
        self._motionKey = nil
    end

    -- Text entrance/exit demo: the runtime's own preview motion, applied to the copy.
    function frame:ApplyTextMotion(entry)
        local settings = entry and entry.settings or {}
        local motion = settings.textAnimation or "none"
        local key = tostring(entry) .. ":" .. tostring(motion) .. ":" .. tostring(settings.textFadeInDirection)
            .. ":" .. tostring(settings.textFadeOutDirection)
        if self._motionKey == key then return end
        self:StopMotion()
        self._motionKey = key
        local visuals = DDingUI.RestrictedAuraVisuals
        if motion ~= "none" and visuals and visuals.ApplyTextPreviewMotion then
            visuals:ApplyTextPreviewMotion(self.host, motion,
                settings.textFadeInDirection or "NONE", settings.textFadeOutDirection or "NONE")
        end
    end

    function frame:ShowHint(message, offerToggle)
        local reader = GUI.DashboardPreview
        if reader then reader.Clear(self.host) end
        self:StopMotion()
        self.hint:SetText(message)
        self.hint:Show()
        if self.toggle then
            self.toggle:SetShown(offerToggle == true)
            if offerToggle and self.toggle.text then
                self.toggle.text:SetText(PreviewModeEnabled() and T("Hide from screen", "화면 미리보기 끄기")
                    or T("Show on screen", "화면 미리보기 켜기"))
            end
        end
    end

    function frame:Refresh(entry, trackedBuffs)
        self._entry = entry
        self._trackedBuffs = trackedBuffs
        if not entry then
            self.name:SetText("")
            self.mode:SetText("")
            self:ShowHint(L["Select a tracker to preview"] or "Select a tracker to preview", false)
            return
        end

        local displayType = entry.isGroup and "group" or (entry.displayType or "bar")
        self.name:SetText(entry.name or (L["Unnamed Tracker"] or "Unnamed Tracker"))
        if not entry.isGroup and not VISUAL_TYPES[displayType] then
            self.mode:SetText(displayType:upper())
            self:ShowHint(T("Tracker without screen display", "화면 표시가 없는 추적기입니다 (소리·트리거 전용)"), false)
            return
        end

        local sources, expected = CollectSources(entry, trackedBuffs)
        local reader = GUI.DashboardPreview
        local color = displayType == "ring" and RingColor(entry)
            or (entry.settings and entry.settings.barColor)
        if #sources > 0 and reader and reader.PaintFit then
            local _, partial, ratio = reader.PaintFit(self.host, sources, color, 8)
            if ratio then
                self.hint:Hide()
                if self.toggle then self.toggle:Hide() end
                local sizeText = ratio >= 0.995 and T("Actual size", "실제 크기")
                    or string.format(T("Scaled to %d%%", "%d%%로 축소"), math.floor(ratio * 100 + 0.5))
                if partial then sizeText = sizeText .. "  ·  " .. T("Display limited", "표시 제한") end
                self.mode:SetText(displayType:upper() .. "  ·  " .. sizeText)
                if displayType == "text" then self:ApplyTextMotion(entry) else self:StopMotion() end
                return
            end
        end

        self.mode:SetText(displayType:upper())
        if entry.disabled then
            self:ShowHint(T("Tracker is disabled", "비활성화된 추적기입니다"), false)
        elseif expected == 0 then
            self:ShowHint(T("Group has no visible trackers", "화면에 표시되는 하위 추적기가 없습니다"), false)
        elseif PreviewModeEnabled() then
            self:ShowHint(T("Tracker is not drawn on screen yet",
                "화면 미리보기가 켜져 있지만 이 추적기는 아직 그려지지 않았습니다"), true)
        else
            self:ShowHint(T("Tracker preview hint",
                "지금 화면에 표시되지 않습니다. 화면 미리보기를 켜면 실제 표시가 그대로 복사됩니다"), true)
        end
    end

    frame:SetScript("OnHide", function(self)
        self:StopMotion()
        local reader = GUI.DashboardPreview
        if reader then reader.Clear(self.host) end
    end)
    frame:Refresh(nil)
    return frame
end

GUI.CreateTrackerLivePreview = function(parent)
    return Preview:Create(parent)
end
