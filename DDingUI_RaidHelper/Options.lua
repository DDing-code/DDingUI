local _, ns = ...

local Options = {}
ns.Options = Options

local BRAND_ICON = "Interface\\AddOns\\DDingUI_RaidHelper\\Media\\RaidHelper_Icon.tga"
local CONTENT_WIDTH = 540
local MIN_TIMELINE_SCALE = 0.6
local MAX_TIMELINE_SCALE = 1.6
local MIN_TIMELINE_WIDTH = 200
local MAX_TIMELINE_WIDTH = 1200
-- [STYLE] C안 (2026-10-10): height = bar + cooldown rail. Saved values from the old
-- four-row window (170~420) read as the new default rather than being clamped.
local MIN_TIMELINE_HEIGHT = 80
local MAX_TIMELINE_HEIGHT = 160
local DEFAULT_TIMELINE_HEIGHT = 98
local LEGACY_TIMELINE_HEIGHT_FLOOR = 170
local MIN_OPTIONS_SCALE = 0.5 -- [STYLE] title-bar "GUI 크기" range (StyleLib 1.2 default)
local MAX_OPTIONS_SCALE = 1.5

local function ClampNumber(value, minimum, maximum, fallback)
    value = tonumber(value)
    if not value then return fallback end
    return math.min(maximum, math.max(minimum, value))
end

local function ResolveTimelineHeight(value)
    value = tonumber(value)
    if not value or value >= LEGACY_TIMELINE_HEIGHT_FLOOR then return DEFAULT_TIMELINE_HEIGHT end
    return ClampNumber(value, MIN_TIMELINE_HEIGHT, MAX_TIMELINE_HEIGHT, DEFAULT_TIMELINE_HEIGHT)
end

local function IsInCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown()
end

local function UnpackColor(color)
    return color[1], color[2], color[3], color[4] or 1
end

local function GetAddonVersion()
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        return C_AddOns.GetAddOnMetadata(ns.addonName, "Version") or "261020"
    end
    if type(GetAddOnMetadata) == "function" then
        return GetAddOnMetadata(ns.addonName, "Version") or "261020"
    end
    return "261020"
end

local function CreateText(parent, fontPath, size, color, text, width)
    local label = parent:CreateFontString(nil, "ARTWORK")
    label:SetFont(fontPath, size, "OUTLINE")
    label:SetTextColor(UnpackColor(color))
    label:SetJustifyH("LEFT")
    label:SetJustifyV("TOP")
    if width then label:SetWidth(width) end
    if text then label:SetText(text) end
    return label
end

function Options:ShouldShowTooltips()
    return ns.db and ns.db.showTooltips == true
end

function Options:ShouldShowUpcomingCooldowns()
    return not ns.db or ns.db.showUpcomingCooldowns ~= false
end

function Options:ShouldPlayCountdownVoice()
    return not ns.db or ns.db.countdownVoice ~= false
end

function Options:GetRequestedTooltipSetting()
    if self.pendingShowTooltips ~= nil then
        return self.pendingShowTooltips
    end
    return self:ShouldShowTooltips()
end

function Options:GetRequestedUpcomingCooldownSetting()
    if self.pendingShowUpcomingCooldowns ~= nil then
        return self.pendingShowUpcomingCooldowns
    end
    return self:ShouldShowUpcomingCooldowns()
end

function Options:GetRequestedTimelineScale()
    if self.pendingTimelineScale ~= nil then
        return self.pendingTimelineScale
    end
    return ClampNumber(ns.db and ns.db.timelineScale, MIN_TIMELINE_SCALE, MAX_TIMELINE_SCALE, 1.0)
end

function Options:GetRequestedBackgroundAlpha()
    if self.pendingBackgroundAlpha ~= nil then
        return self.pendingBackgroundAlpha
    end
    return ClampNumber(ns.db and ns.db.backgroundAlpha, 0, 1, 1.0)
end

function Options:GetRequestedTimelineWidth()
    if self.pendingTimelineWidth ~= nil then
        return self.pendingTimelineWidth
    end
    return ClampNumber(
        ns.db and ns.db.timelineWidth,
        MIN_TIMELINE_WIDTH,
        MAX_TIMELINE_WIDTH,
        680
    )
end

function Options:GetRequestedTimelineHeight()
    if self.pendingTimelineHeight ~= nil then
        return self.pendingTimelineHeight
    end
    return ResolveTimelineHeight(ns.db and ns.db.timelineHeight)
end

-- [STYLE] Settings-window scale only; the combat timeline keeps timelineScale.
function Options:GetOptionsScale()
    return ClampNumber(ns.db and ns.db.optionsScale, MIN_OPTIONS_SCALE, MAX_OPTIONS_SCALE, 1.0)
end

function Options:SetOptionsScale(value)
    if not ns.db then return false end
    ns.db.optionsScale = ClampNumber(value, MIN_OPTIONS_SCALE, MAX_OPTIONS_SCALE, 1.0)
    return true
end

function Options:RefreshCheckbox()
    if not self.tooltipCheckbox and not self.upcomingCooldownCheckbox and not self.countdownVoiceCheckbox then return end

    self.syncingCheckbox = true
    if self.tooltipCheckbox then
        self.tooltipCheckbox:SetChecked(self:GetRequestedTooltipSetting())
    end
    if self.upcomingCooldownCheckbox then
        self.upcomingCooldownCheckbox:SetChecked(self:GetRequestedUpcomingCooldownSetting())
    end
    if self.countdownVoiceCheckbox then
        self.countdownVoiceCheckbox:SetChecked(self:ShouldPlayCountdownVoice())
    end
    if self.countdownVoiceDropdown then
        self.countdownVoiceDropdown:SetValue(ns.TimelineUI:GetCountdownVoicePack())
    end
    self.syncingCheckbox = false
end

function Options:RefreshDisplayControls()
    if not self.timelineScaleSlider
        and not self.backgroundAlphaSlider
        and not self.timelineWidthSlider
        and not self.timelineHeightSlider then
        return
    end

    self.syncingDisplayControls = true
    if self.timelineScaleSlider and self.timelineScaleSlider.slider then
        self.timelineScaleSlider.slider:SetValue(self:GetRequestedTimelineScale() * 100)
    end
    if self.backgroundAlphaSlider and self.backgroundAlphaSlider.slider then
        self.backgroundAlphaSlider.slider:SetValue(self:GetRequestedBackgroundAlpha() * 100)
    end
    if self.timelineWidthSlider and self.timelineWidthSlider.slider then
        self.timelineWidthSlider.slider:SetValue(self:GetRequestedTimelineWidth())
    end
    if self.timelineHeightSlider and self.timelineHeightSlider.slider then
        self.timelineHeightSlider.slider:SetValue(self:GetRequestedTimelineHeight())
    end
    self.syncingDisplayControls = false
end

function Options:RefreshProfileSummary()
    if not self.profileSummary then return end

    local profile = ns.Engine and ns.Engine:GetHealerProfile()
    local model = ns.Engine and ns.Engine:GetModel()
    local encounterName = ns.Engine and ns.Engine.encounterName or (model and model.name)
    local prefix = encounterName and (encounterName .. "\n") or ""
    local summary = ns.HealerProfileUI and ns.HealerProfileUI:GetSummary(profile)
        or "현재 전문화의 수집 데이터가 없습니다."
    self.profileSummary:SetText(prefix .. summary)
    if self.profileButton and self.profileButton.SetDisabledState then
        self.profileButton:SetDisabledState(profile == nil)
    end
end

function Options:RefreshDataSummary()
    if not self.dataSummary then return end

    local summary = ns.Registry and ns.Registry:GetDataSummary() or nil
    if not summary or summary.modelCount == 0 then
        self.dataSummary:SetText("설치된 실데이터 모델이 없습니다.")
        return
    end

    local generatedAt = summary.latestGeneratedAt or "생성 시각 없음"
    generatedAt = generatedAt:gsub("T", " "):gsub("%+00:00$", " UTC")
    local dpsLine = summary.dpsModelCount and summary.dpsModelCount > 0
        and string.format("\n딜러 모델 %d개 · 표본 제한 %d개",
            summary.dpsModelCount, summary.limitedDpsModelCount or 0) or ""
    self.dataSummary:SetText(string.format(
        "실데이터 %d개\n영웅 %d · 신화 %d\n최근 생성 %s%s",
        summary.modelCount,
        summary.heroicCount,
        summary.mythicCount,
        generatedAt,
        dpsLine
    ))
end

function Options:GetRequestedCooldownVisible(specID, spellID)
    local pendingSpec = self.pendingCooldownVisibility
        and (self.pendingCooldownVisibility[specID]
            or self.pendingCooldownVisibility[tostring(specID)])
    if type(pendingSpec) == "table" then
        local pending = pendingSpec[spellID]
        if pending == nil then pending = pendingSpec[tostring(spellID)] end
        if pending ~= nil then return pending == true end
    end
    if ns.CooldownCatalog then
        return ns.CooldownCatalog:IsShown(
            specID,
            spellID,
            ns.db and ns.db.cooldownVisibility
        )
    end
    return true
end

function Options:RefreshCooldownControls()
    if not self.cooldownSpecFrames then return end

    if not IsInCombat() and ns.Engine and ns.Engine.RefreshPlayerSpecialization then
        ns.Engine:RefreshPlayerSpecialization()
    end
    local specID = ns.Engine and ns.Engine.playerSpecID or nil
    local spec = ns.CooldownCatalog and ns.CooldownCatalog:GetSpec(specID) or nil

    for key, frame in pairs(self.cooldownSpecFrames) do
        frame:SetShown(key == specID and spec ~= nil)
    end
    if self.cooldownNoSpecText then
        self.cooldownNoSpecText:SetShown(spec == nil)
    end
    if self.cooldownSpecText then
        self.cooldownSpecText:SetText(spec and spec.name or "현재 전문화의 쿨기 목록이 없습니다.")
    end
    if not spec then return end

    self.syncingCooldownControls = true
    for _, record in ipairs(self.cooldownCheckboxes[specID] or {}) do
        record.checkbox:SetChecked(
            self:GetRequestedCooldownVisible(specID, record.spellID)
        )
    end
    self.syncingCooldownControls = false
end

function Options:RefreshAll()
    self:RefreshCheckbox()
    self:RefreshDisplayControls()
    self:RefreshProfileSummary()
    self:RefreshDataSummary()
    self:RefreshCooldownControls()
    if self.RefreshAlertControls then self:RefreshAlertControls() end
    if self.RefreshTimelineStyleControls then self:RefreshTimelineStyleControls() end
    if self.RefreshPreviewButton then self:RefreshPreviewButton() end
end

function Options:ReloadData()
    if IsInCombat() then
        ns:Print("전투 중에는 데이터를 다시 불러올 수 없습니다.")
        return false
    end
    if type(ReloadUI) == "function" then
        ReloadUI()
        return true
    end
    ns:Print("UI 다시 불러오기를 사용할 수 없습니다.")
    return false
end

function Options:ApplyTooltipSetting(enabled)
    if not ns.db then return false end

    ns.db.showTooltips = enabled == true
    if not ns.db.showTooltips and GameTooltip then
        GameTooltip:Hide()
    end
    self:RefreshCheckbox()
    return true
end

function Options:SetTooltipsEnabled(enabled)
    enabled = enabled == true
    if IsInCombat() then
        self.pendingShowTooltips = enabled
        self:RefreshCheckbox()
        ns:Print(enabled and "툴팁 켜기" or "툴팁 끄기", "설정은 전투 종료 후 적용됩니다.")
        return false, "deferred"
    end

    self.pendingShowTooltips = nil
    self:ApplyTooltipSetting(enabled)
    ns:Print(enabled and "마커 툴팁을 켰습니다." or "마커 툴팁을 껐습니다.")
    return true
end

function Options:ApplyUpcomingCooldownSetting(enabled)
    if not ns.db then return false end

    ns.db.showUpcomingCooldowns = enabled == true
    if ns.TimelineUI then
        if not ns.db.showUpcomingCooldowns and ns.TimelineUI.upcomingPanel then
            ns.TimelineUI.upcomingPanel:Hide()
        elseif ns.TimelineUI.UpdateView
            and ns.Engine and ns.Engine.IsRunning and ns.Engine:IsRunning() then
            ns.TimelineUI:UpdateView()
        end
    end
    self:RefreshCheckbox()
    return true
end

function Options:SetUpcomingCooldownsEnabled(enabled)
    enabled = enabled == true
    if IsInCombat() then
        self.pendingShowUpcomingCooldowns = enabled
        self:RefreshCheckbox()
        ns:Print(enabled and "예정 쿨기 목록 켜기" or "예정 쿨기 목록 끄기", "설정은 전투 종료 후 적용됩니다.")
        return false, "deferred"
    end

    self.pendingShowUpcomingCooldowns = nil
    self:ApplyUpcomingCooldownSetting(enabled)
    ns:Print(enabled and "예정 쿨기 목록을 켰습니다." or "예정 쿨기 목록을 껐습니다.")
    return true
end

-- [STYLE] "곧 사용" alert layout (2026-10-10): sizes, alignment, growth, rows, width,
-- lead time and element toggles in ns.db.alertStyle. The alert is the addon's own unsecured
-- frame, so changes apply at once, also in combat.
function Options:GetAlertStyle()
    if ns.TimelineUI and ns.TimelineUI.GetAlertStyle then
        return ns.TimelineUI:GetAlertStyle()
    end
    return {}
end

function Options:SetAlertStyleValue(key, value)
    if not ns.db then return false end
    if type(ns.db.alertStyle) ~= "table" then ns.db.alertStyle = {} end
    ns.db.alertStyle[key] = value
    if ns.TimelineUI and ns.TimelineUI.ApplyAlertStyle then
        ns.TimelineUI:ApplyAlertStyle()
    end
    return true
end

function Options:ResetAlertStyle()
    if not ns.db then return false end
    ns.db.alertStyle = {}
    if ns.TimelineUI and ns.TimelineUI.ApplyAlertStyle then
        ns.TimelineUI:ApplyAlertStyle()
    end
    if self.RefreshAlertControls then self:RefreshAlertControls() end
    ns:Print("리마인더 모양을 기본값으로 되돌렸습니다.")
    return true
end

-- [STYLE] Timeline detail options (2026-10-11 사용자 요청): icon sizes, shown range, past-icon
-- opacity and element switches in ns.db.timelineStyle (range keys stay at windowPast/Future).
-- Same combat rule as the other timeline display settings: changes wait for combat to end.
local function GetTimelineStyleSpec(key)
    local spec = ns.TimelineUI and ns.TimelineUI.TIMELINE_STYLE_SPEC
    return spec and spec[key] or nil
end

function Options:GetRequestedTimelineStyle()
    local style = {}
    if ns.TimelineUI and ns.TimelineUI.GetTimelineStyle then
        for key, value in pairs(ns.TimelineUI:GetTimelineStyle()) do style[key] = value end
    end
    for key, value in pairs(self.pendingTimelineStyle or {}) do style[key] = value end
    return style
end

function Options:ApplyTimelineStyleValue(key, value)
    local spec = GetTimelineStyleSpec(key)
    if not ns.db or not spec then return false end
    if spec.root then
        ns.db[key] = value
    else
        if type(ns.db.timelineStyle) ~= "table" then ns.db.timelineStyle = {} end
        ns.db.timelineStyle[key] = value
    end
    if ns.TimelineUI.ApplyTimelineStyle then ns.TimelineUI:ApplyTimelineStyle() end
    return true
end

function Options:SetTimelineStyleValue(key, value)
    if not GetTimelineStyleSpec(key) then return false end
    if IsInCombat() then
        self.pendingTimelineStyle = self.pendingTimelineStyle or {}
        self.pendingTimelineStyle[key] = value
        return false, "deferred"
    end

    if self.pendingTimelineStyle then self.pendingTimelineStyle[key] = nil end
    return self:ApplyTimelineStyleValue(key, value)
end

function Options:ResetTimelineStyle()
    if not ns.db then return false end
    if IsInCombat() then
        ns:Print("타임라인 세부 설정은 전투가 끝난 뒤 되돌릴 수 있습니다.")
        return false
    end

    self.pendingTimelineStyle = nil
    ns.db.timelineStyle = {}
    for key, spec in pairs(ns.TimelineUI and ns.TimelineUI.TIMELINE_STYLE_SPEC or {}) do
        if spec.root then ns.db[key] = spec.default end
    end
    if ns.TimelineUI and ns.TimelineUI.ApplyTimelineStyle then
        ns.TimelineUI:ApplyTimelineStyle()
    end
    if self.RefreshTimelineStyleControls then self:RefreshTimelineStyleControls() end
    ns:Print("타임라인 세부 설정을 기본값으로 되돌렸습니다.")
    return true
end

-- [STYLE] Voice countdown only plays sounds, so it applies at once, even in combat.
function Options:SetCountdownVoiceEnabled(enabled)
    if not ns.db then return false end
    ns.db.countdownVoice = enabled == true
    self:RefreshCheckbox()
    ns:Print(enabled and "리마인더 음성 카운트를 켰습니다." or "리마인더 음성 카운트를 껐습니다.")
    return true
end

function Options:SetCountdownVoicePack(pack)
    if not ns.db or type(pack) ~= "string" or not ns.TimelineUI.COUNTDOWN_SOUNDS[pack] then return false end
    ns.db.countdownVoicePack = pack
    -- [STYLE] Cancel queued preview numbers so a sample never mixes two packs.
    ns.TimelineUI.countdownPreviewToken = (ns.TimelineUI.countdownPreviewToken or 0) + 1
    self:RefreshCheckbox()
    return true
end

function Options:ApplyTimelineScale(value)
    if not ns.db then return false end

    ns.db.timelineScale = ClampNumber(value, MIN_TIMELINE_SCALE, MAX_TIMELINE_SCALE, 1.0)
    if ns.TimelineUI and ns.TimelineUI.ApplyDisplaySettings then
        ns.TimelineUI:ApplyDisplaySettings()
    end
    self:RefreshDisplayControls()
    return true
end

function Options:SetTimelineScale(value)
    value = ClampNumber(value, MIN_TIMELINE_SCALE, MAX_TIMELINE_SCALE, 1.0)
    if IsInCombat() then
        self.pendingTimelineScale = value
        self:RefreshDisplayControls()
        return false, "deferred"
    end

    self.pendingTimelineScale = nil
    return self:ApplyTimelineScale(value)
end

function Options:ApplyTimelineWidth(value)
    if not ns.db then return false end

    ns.db.timelineWidth = ClampNumber(
        value,
        MIN_TIMELINE_WIDTH,
        MAX_TIMELINE_WIDTH,
        680
    )
    if ns.TimelineUI and ns.TimelineUI.ApplyDisplaySettings then
        ns.TimelineUI:ApplyDisplaySettings()
    end
    self:RefreshDisplayControls()
    return true
end

function Options:SetTimelineWidth(value)
    value = ClampNumber(value, MIN_TIMELINE_WIDTH, MAX_TIMELINE_WIDTH, 680)
    if IsInCombat() then
        self.pendingTimelineWidth = value
        self:RefreshDisplayControls()
        return false, "deferred"
    end

    self.pendingTimelineWidth = nil
    return self:ApplyTimelineWidth(value)
end

function Options:ApplyTimelineHeight(value)
    if not ns.db then return false end

    ns.db.timelineHeight = ResolveTimelineHeight(value)
    if ns.TimelineUI and ns.TimelineUI.ApplyDisplaySettings then
        ns.TimelineUI:ApplyDisplaySettings()
    end
    self:RefreshDisplayControls()
    return true
end

function Options:SetTimelineHeight(value)
    value = ResolveTimelineHeight(value)
    if IsInCombat() then
        self.pendingTimelineHeight = value
        self:RefreshDisplayControls()
        return false, "deferred"
    end

    self.pendingTimelineHeight = nil
    return self:ApplyTimelineHeight(value)
end

function Options:ApplyBackgroundAlpha(value)
    if not ns.db then return false end

    ns.db.backgroundAlpha = ClampNumber(value, 0, 1, 1.0)
    if ns.TimelineUI and ns.TimelineUI.ApplyDisplaySettings then
        ns.TimelineUI:ApplyDisplaySettings()
    end
    self:RefreshDisplayControls()
    return true
end

function Options:SetBackgroundAlpha(value)
    value = ClampNumber(value, 0, 1, 1.0)
    if IsInCombat() then
        self.pendingBackgroundAlpha = value
        self:RefreshDisplayControls()
        return false, "deferred"
    end

    self.pendingBackgroundAlpha = nil
    return self:ApplyBackgroundAlpha(value)
end

function Options:ApplyCooldownVisible(specID, spellID, shown)
    if not ns.db then return false end
    specID = tonumber(specID)
    spellID = tonumber(spellID)
    if not specID or not spellID then return false end

    ns.db.cooldownVisibility = ns.db.cooldownVisibility or {}
    ns.db.cooldownVisibility[specID] = ns.db.cooldownVisibility[specID] or {}
    ns.db.cooldownVisibility[specID][spellID] = shown == true
    if ns.TimelineUI and ns.TimelineUI.UpdateView
        and ns.Engine and ns.Engine.IsRunning and ns.Engine:IsRunning() then
        ns.TimelineUI:UpdateView()
    end
    return true
end

function Options:SetCooldownVisible(specID, spellID, shown)
    specID = tonumber(specID)
    spellID = tonumber(spellID)
    shown = shown == true
    if not specID or not spellID then return false end

    if IsInCombat() then
        self.pendingCooldownVisibility = self.pendingCooldownVisibility or {}
        self.pendingCooldownVisibility[specID] = self.pendingCooldownVisibility[specID] or {}
        self.pendingCooldownVisibility[specID][spellID] = shown
        self:RefreshCooldownControls()
        return false, "deferred"
    end

    if self.pendingCooldownVisibility and self.pendingCooldownVisibility[specID] then
        self.pendingCooldownVisibility[specID][spellID] = nil
    end
    self:ApplyCooldownVisible(specID, spellID, shown)
    self:RefreshCooldownControls()
    return true
end

function Options:SetCooldownPreset(mode)
    local specID = ns.Engine and ns.Engine.playerSpecID or nil
    local spec = ns.CooldownCatalog and ns.CooldownCatalog:GetSpec(specID) or nil
    if not spec then return false end

    for _, spell in ipairs(spec.spells) do
        local shown
        if mode == "major" then
            shown = spell.category == "major"
        elseif mode == "healing" then
            shown = spell.category == "major" or spell.category == "semi"
        elseif mode == "all" then
            shown = true
        elseif mode == "none" then
            shown = false
        else
            shown = spell.defaultShown ~= false
        end
        self:SetCooldownVisible(specID, spell.spellID, shown)
    end
    self:RefreshCooldownControls()
    return true
end

function Options:ApplyPendingSettings()
    if IsInCombat() then return false end

    local applied = false
    if self.pendingShowTooltips ~= nil then
        local enabled = self.pendingShowTooltips
        self.pendingShowTooltips = nil
        self:ApplyTooltipSetting(enabled)
        applied = true
    end
    if self.pendingShowUpcomingCooldowns ~= nil then
        local enabled = self.pendingShowUpcomingCooldowns
        self.pendingShowUpcomingCooldowns = nil
        self:ApplyUpcomingCooldownSetting(enabled)
        applied = true
    end
    if self.pendingTimelineScale ~= nil then
        local value = self.pendingTimelineScale
        self.pendingTimelineScale = nil
        self:ApplyTimelineScale(value)
        applied = true
    end
    if self.pendingTimelineWidth ~= nil then
        local value = self.pendingTimelineWidth
        self.pendingTimelineWidth = nil
        self:ApplyTimelineWidth(value)
        applied = true
    end
    if self.pendingTimelineHeight ~= nil then
        local value = self.pendingTimelineHeight
        self.pendingTimelineHeight = nil
        self:ApplyTimelineHeight(value)
        applied = true
    end
    if self.pendingBackgroundAlpha ~= nil then
        local value = self.pendingBackgroundAlpha
        self.pendingBackgroundAlpha = nil
        self:ApplyBackgroundAlpha(value)
        applied = true
    end
    if self.pendingTimelineStyle then
        local pending = self.pendingTimelineStyle
        self.pendingTimelineStyle = nil
        for key, value in pairs(pending) do
            self:ApplyTimelineStyleValue(key, value)
            applied = true
        end
        if self.RefreshTimelineStyleControls then self:RefreshTimelineStyleControls() end
    end
    if self.pendingCooldownVisibility then
        local pending = self.pendingCooldownVisibility
        self.pendingCooldownVisibility = nil
        for specID, spells in pairs(pending) do
            for spellID, shown in pairs(spells) do
                self:ApplyCooldownVisible(specID, spellID, shown)
                applied = true
            end
        end
        self:RefreshCooldownControls()
    end

    if applied then
        ns:Print("대기 중이던 표시 설정을 적용했습니다.")
    end
    return applied
end

function Options:SelectPage(key)
    key = self.pages and self.pages[key] and key or "timeline"
    if not self.pages then return end

    for pageKey, page in pairs(self.pages) do
        page:SetShown(pageKey == key)
    end
    self.activePage = key
    if self.contentScroll and self.contentScroll.SetVerticalScroll then
        self.contentScroll:SetVerticalScroll(0)
    end
    if self.tree and self.tree.GetSelected and self.tree:GetSelected() ~= key then
        self.tree:SetSelected(key)
    end
    self:RefreshAll()
end

function Options:Open(pageKey)
    if IsInCombat() then
        ns:Print("설정 창은 전투가 끝난 뒤 열 수 있습니다.")
        return false
    end

    if not self.initialized then self:Initialize() end
    if not self.frame then
        ns:Print("RaidHelper 설정 창을 만들지 못했습니다.")
        return false
    end

    self:SelectPage(pageKey or self.activePage or "timeline")
    if self.frame.ShowAnimated then
        self.frame:ShowAnimated()
    else
        self.frame:Show()
    end
    return true
end

function Options:Close()
    if not self.frame then return false end
    if self.frame.HideAnimated then
        self.frame:HideAnimated()
    else
        self.frame:Hide()
    end
    return true
end

function Options:Toggle(pageKey)
    if self.frame and self.frame:IsShown() and not self.frame._ddslPanelClosing then
        return self:Close()
    end
    return self:Open(pageKey)
end

function Options:CreatePage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, -18)
    page:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -20, -18)
    page:SetHeight(450)
    page:Hide()
    return page
end

function Options:CreateTimelinePage(parent, styleLib, fontPath, titleSize, normalSize, smallSize, colors)
    local page = self:CreatePage(parent)

    local title = CreateText(page, fontPath, titleSize, colors.text.highlight, "타임라인 설정", CONTENT_WIDTH)
    title:SetPoint("TOPLEFT")

    local description = CreateText(
        page,
        fontPath,
        normalSize,
        colors.text.normal,
        "전투 중 표시되는 피해 파형과 기믹·전문화 쿨기 마커의 동작을 설정합니다.",
        CONTENT_WIDTH
    )
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)

    local displayHeader = styleLib.CreateSectionHeader(page, "RaidHelper", "화면 표시", { showLine = true })
    displayHeader:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -70)
    displayHeader:SetWidth(CONTENT_WIDTH)

    local timelineScaleSlider = styleLib.CreateSlider(
        page,
        "RaidHelper",
        "전체 크기 (%)",
        MIN_TIMELINE_SCALE * 100,
        MAX_TIMELINE_SCALE * 100,
        5,
        self:GetRequestedTimelineScale() * 100,
        {
            width = 252,
            onChange = function(value)
                if Options.syncingDisplayControls then return end
                Options:SetTimelineScale(value / 100)
            end,
        }
    )
    timelineScaleSlider:SetPoint("TOPLEFT", displayHeader, "BOTTOMLEFT", 0, -8)

    local backgroundAlphaSlider = styleLib.CreateSlider(
        page,
        "RaidHelper",
        "배경 불투명도 (%)",
        0,
        100,
        5,
        self:GetRequestedBackgroundAlpha() * 100,
        {
            width = 252,
            onChange = function(value)
                if Options.syncingDisplayControls then return end
                Options:SetBackgroundAlpha(value / 100)
            end,
        }
    )
    backgroundAlphaSlider:SetPoint("TOPLEFT", displayHeader, "BOTTOMLEFT", 278, -8)

    local timelineWidthSlider = styleLib.CreateSlider(
        page,
        "RaidHelper",
        "너비 (px)",
        MIN_TIMELINE_WIDTH,
        MAX_TIMELINE_WIDTH,
        20,
        self:GetRequestedTimelineWidth(),
        {
            width = 252,
            onChange = function(value)
                if Options.syncingDisplayControls then return end
                Options:SetTimelineWidth(value)
            end,
        }
    )
    timelineWidthSlider:SetPoint("TOPLEFT", displayHeader, "BOTTOMLEFT", 0, -70)

    local timelineHeightSlider = styleLib.CreateSlider(
        page,
        "RaidHelper",
        "높이 (px)",
        MIN_TIMELINE_HEIGHT,
        MAX_TIMELINE_HEIGHT,
        2,
        self:GetRequestedTimelineHeight(),
        {
            width = 252,
            onChange = function(value)
                if Options.syncingDisplayControls then return end
                Options:SetTimelineHeight(value)
            end,
        }
    )
    timelineHeightSlider:SetPoint("TOPLEFT", displayHeader, "BOTTOMLEFT", 278, -70)

    local tooltipCheckbox = styleLib.CreateCheckbox(
        page,
        "RaidHelper",
        "기믹·전문화 쿨기 마커 툴팁 표시",
        self:ShouldShowTooltips(),
        {
            onChange = function(value)
                if Options.syncingCheckbox then return end
                Options:SetTooltipsEnabled(value)
            end,
        }
    )
    tooltipCheckbox:SetPoint("TOPLEFT", timelineWidthSlider, "BOTTOMLEFT", 0, -5)
    tooltipCheckbox:SetWidth(400)

    local upcomingCooldownCheckbox = styleLib.CreateCheckbox(
        page,
        "RaidHelper",
        "리마인더 표시 (곧 사용할 쿨기)",
        self:ShouldShowUpcomingCooldowns(),
        {
            onChange = function(value)
                if Options.syncingCheckbox then return end
                Options:SetUpcomingCooldownsEnabled(value)
            end,
        }
    )
    upcomingCooldownCheckbox:SetPoint("TOPLEFT", tooltipCheckbox, "BOTTOMLEFT", 0, -5)
    upcomingCooldownCheckbox:SetWidth(400)

    local combatNote = CreateText(
        page,
        fontPath,
        smallSize,
        colors.text.dim,
        "전투 중 변경한 값은 현재 전투에 적용하지 않고 전투 종료 후 안전하게 반영합니다.",
        CONTENT_WIDTH
    )
    combatNote:SetPoint("TOPLEFT", upcomingCooldownCheckbox, "BOTTOMLEFT", 20, -7)

    local quickHeader = styleLib.CreateSectionHeader(page, "RaidHelper", "빠른 실행", { showLine = true })
    quickHeader:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -325)
    quickHeader:SetWidth(CONTENT_WIDTH)

    local previewButton = styleLib.CreateButton(page, "RaidHelper", "미리보기", function()
        if ns.TimelineUI and ns.TimelineUI.TogglePreviewMode then
            ns.TimelineUI:TogglePreviewMode()
            Options:RefreshPreviewButton()
        end
    end, { width = 150, height = 26 })
    previewButton:SetPoint("TOPLEFT", quickHeader, "BOTTOMLEFT", 0, -8)

    local resetButton = styleLib.CreateButton(page, "RaidHelper", "위치 초기화", function()
        if ns.TimelineUI then ns.TimelineUI:ResetPosition() end
        ns:Print("프레임 위치를 초기화했습니다.")
    end, { width = 108, height = 26 })
    resetButton:SetPoint("LEFT", previewButton, "RIGHT", 8, 0)

    local usageHeader = styleLib.CreateSectionHeader(page, "RaidHelper", "미니맵 버튼", { showLine = true })
    usageHeader:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -410)
    usageHeader:SetWidth(CONTENT_WIDTH)

    local usage = CreateText(
        page,
        fontPath,
        normalSize,
        colors.text.normal,
        "좌클릭으로 이 설정 창을 열고 닫습니다. 우클릭은 위치 편집 모드를 켜거나 끕니다. 버튼을 드래그하면 위치가 저장됩니다.",
        CONTENT_WIDTH
    )
    usage:SetPoint("TOPLEFT", usageHeader, "BOTTOMLEFT", 0, -8)

    self.tooltipCheckbox = tooltipCheckbox
    self.upcomingCooldownCheckbox = upcomingCooldownCheckbox
    self.timelineScaleSlider = timelineScaleSlider
    self.backgroundAlphaSlider = backgroundAlphaSlider
    self.timelineWidthSlider = timelineWidthSlider
    self.timelineHeightSlider = timelineHeightSlider
    self.previewButton = previewButton
    return page
end

function Options:CreateCooldownPage(parent, styleLib, fontPath, titleSize, normalSize, smallSize, colors)
    local page = self:CreatePage(parent)

    local title = CreateText(page, fontPath, titleSize, colors.text.highlight, "쿨기 표시", CONTENT_WIDTH)
    title:SetPoint("TOPLEFT")

    local description = CreateText(
        page,
        fontPath,
        normalSize,
        colors.text.normal,
        "현재 전문화에서 타임라인에 표시할 주문을 선택합니다. 주요·보조·외생기·개인 유틸로 구분합니다.",
        CONTENT_WIDTH
    )
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)

    local specHeader = styleLib.CreateSectionHeader(page, "RaidHelper", "현재 전문화", { showLine = true })
    specHeader:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -76)
    specHeader:SetWidth(CONTENT_WIDTH)

    local specText = CreateText(page, fontPath, normalSize, colors.text.highlight, "", 150)
    specText:SetPoint("TOPLEFT", specHeader, "BOTTOMLEFT", 0, -10)

    local majorButton = styleLib.CreateButton(page, "RaidHelper", "주요만", function()
        Options:SetCooldownPreset("major")
    end, { width = 76, height = 24 })
    majorButton:SetPoint("TOPLEFT", specHeader, "BOTTOMLEFT", 160, -6)

    local healingButton = styleLib.CreateButton(page, "RaidHelper", "주요 + 세미", function()
        Options:SetCooldownPreset("healing")
    end, { width = 92, height = 24 })
    healingButton:SetPoint("LEFT", majorButton, "RIGHT", 6, 0)

    local allButton = styleLib.CreateButton(page, "RaidHelper", "전체", function()
        Options:SetCooldownPreset("all")
    end, { width = 54, height = 24 })
    allButton:SetPoint("LEFT", healingButton, "RIGHT", 6, 0)

    local noneButton = styleLib.CreateButton(page, "RaidHelper", "전체 해제", function()
        Options:SetCooldownPreset("none")
    end, { width = 70, height = 24 })
    noneButton:SetPoint("LEFT", allButton, "RIGHT", 6, 0)

    local defaultButton = styleLib.CreateButton(page, "RaidHelper", "기본값", function()
        Options:SetCooldownPreset("default")
    end, { width = 64, height = 24 })
    defaultButton:SetPoint("LEFT", noneButton, "RIGHT", 6, 0)

    local listFrame = CreateFrame("Frame", nil, page)
    listFrame:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -132)
    listFrame:SetSize(CONTENT_WIDTH, 310)

    local noSpecText = CreateText(
        listFrame,
        fontPath,
        normalSize,
        colors.text.dim,
        "지원하는 전문화로 변경하면 해당 주문 선택 항목이 자동으로 표시됩니다.",
        CONTENT_WIDTH
    )
    noSpecText:SetPoint("TOPLEFT", 0, -12)

    self.cooldownSpecFrames = {}
    self.cooldownCheckboxes = {}
    for _, specID in ipairs(ns.CooldownCatalog:GetSpecIDs()) do
        local currentSpecID = specID
        local spec = ns.CooldownCatalog and ns.CooldownCatalog:GetSpec(currentSpecID)
        if spec then
            local specFrame = CreateFrame("Frame", nil, listFrame)
            specFrame:SetPoint("TOPLEFT")
            specFrame:SetPoint("BOTTOMRIGHT")
            specFrame:Hide()
            self.cooldownSpecFrames[currentSpecID] = specFrame
            self.cooldownCheckboxes[currentSpecID] = {}

            local cursorY = 0
            for _, group in ipairs(ns.CooldownCatalog:GetGroups()) do
                local groupSpells = {}
                for _, spell in ipairs(spec.spells) do
                    if spell.category == group.key then
                        groupSpells[#groupSpells + 1] = spell
                    end
                end
                if #groupSpells > 0 then
                    local groupLabel = CreateText(
                        specFrame,
                        fontPath,
                        smallSize,
                        colors.text.dim,
                        group.label .. "  ·  " .. group.description,
                        CONTENT_WIDTH
                    )
                    groupLabel:SetPoint("TOPLEFT", specFrame, "TOPLEFT", 0, -cursorY)
                    cursorY = cursorY + 18

                    for index, spell in ipairs(groupSpells) do
                        local currentSpellID = spell.spellID
                        local column = (index - 1) % 2
                        local row = math.floor((index - 1) / 2)
                        local checkbox = styleLib.CreateCheckbox(
                            specFrame,
                            "RaidHelper",
                            ns.CooldownCatalog:GetSpellName(currentSpecID, currentSpellID),
                            spell.defaultShown ~= false,
                            {
                                onChange = function(value)
                                    if Options.syncingCooldownControls then return end
                                    Options:SetCooldownVisible(currentSpecID, currentSpellID, value)
                                end,
                            }
                        )
                        checkbox:SetPoint(
                            "TOPLEFT",
                            specFrame,
                            "TOPLEFT",
                            column * 270,
                            -(cursorY + row * 23)
                        )
                        checkbox:SetWidth(260)
                        self.cooldownCheckboxes[currentSpecID][#self.cooldownCheckboxes[currentSpecID] + 1] = {
                            checkbox = checkbox,
                            spellID = currentSpellID,
                        }
                    end
                    cursorY = cursorY + math.ceil(#groupSpells / 2) * 23 + 5
                end
            end
        end
    end

    local sourceNote = CreateText(
        page,
        fontPath,
        smallSize,
        colors.text.dim,
        "표시 분류는 주요·보조·외생기·개인/유틸로 나뉘며, 실제 시전이 확인된 기술만 타임라인에 표시합니다.",
        CONTENT_WIDTH
    )
    sourceNote:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 4)

    self.cooldownSpecText = specText
    self.cooldownNoSpecText = noSpecText
    return page
end

function Options:CreateProfilePage(parent, styleLib, fontPath, titleSize, normalSize, smallSize, colors)
    local page = self:CreatePage(parent)

    local title = CreateText(page, fontPath, titleSize, colors.text.highlight, "상위 전문화 프로필", CONTENT_WIDTH)
    title:SetPoint("TOPLEFT")

    local description = CreateText(
        page,
        fontPath,
        normalSize,
        colors.text.normal,
        "현재 보스·난이도·전문화와 일치하는 상위 기록의 평균 2차 스탯과 대표 특성을 보여줍니다.",
        CONTENT_WIDTH
    )
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)

    local summaryHeader = styleLib.CreateSectionHeader(page, "RaidHelper", "현재 선택", { showLine = true })
    summaryHeader:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -82)
    summaryHeader:SetWidth(CONTENT_WIDTH)

    local profileSummary = CreateText(page, fontPath, normalSize, colors.text.highlight, "", CONTENT_WIDTH)
    profileSummary:SetPoint("TOPLEFT", summaryHeader, "BOTTOMLEFT", 0, -10)
    profileSummary:SetHeight(54)

    local profileButton = styleLib.CreateButton(page, "RaidHelper", "2차 스탯 · 특성 코드 보기", function()
        if ns.HealerProfileUI then ns.HealerProfileUI:Show() end
    end, { width = 200, height = 26 })
    profileButton:SetPoint("TOPLEFT", profileSummary, "BOTTOMLEFT", 0, -12)

    local note = CreateText(
        page,
        fontPath,
        smallSize,
        colors.text.dim,
        "대표 특성 코드는 현재 게임의 특성 트리 해시와 수집한 노드 정보를 조합해 생성합니다.",
        CONTENT_WIDTH
    )
    note:SetPoint("TOPLEFT", profileButton, "BOTTOMLEFT", 0, -14)

    self.profileSummary = profileSummary
    self.profileButton = profileButton
    return page
end

function Options:CreateDataPage(parent, styleLib, fontPath, titleSize, normalSize, smallSize, colors)
    local page = self:CreatePage(parent)

    local title = CreateText(page, fontPath, titleSize, colors.text.highlight, "데이터 팩", CONTENT_WIDTH)
    title:SetPoint("TOPLEFT")

    local description = CreateText(
        page,
        fontPath,
        normalSize,
        colors.text.normal,
        "Warcraft Logs 공개 로그에서 생성한 데이터 팩의 상태입니다.",
        CONTENT_WIDTH
    )
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)

    local statusHeader = styleLib.CreateSectionHeader(page, "RaidHelper", "설치 상태", { showLine = true })
    statusHeader:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -82)
    statusHeader:SetWidth(CONTENT_WIDTH)

    local dataSummary = CreateText(page, fontPath, normalSize, colors.text.highlight, "", CONTENT_WIDTH)
    dataSummary:SetPoint("TOPLEFT", statusHeader, "BOTTOMLEFT", 0, -10)
    dataSummary:SetHeight(70)

    local reloadButton = styleLib.CreateButton(page, "RaidHelper", "데이터 다시 불러오기", function()
        Options:ReloadData()
    end, { width = 164, height = 26 })
    reloadButton:SetPoint("TOPLEFT", dataSummary, "BOTTOMLEFT", 0, -12)

    self.dataSummary = dataSummary
    self.reloadButton = reloadButton
    return page
end

function Options:Initialize()
    if self.initialized then return end

    local styleLib = ns.GetStyleLib and ns:GetStyleLib()
        or _G.DDingUI_RaidHelperStyleLib -- [REFACTOR] private embedded copy only
    if not styleLib
        or not styleLib.CreateSettingsPanel
        or not styleLib.CreateTreeMenu
        or not styleLib.CreateCheckbox
        or not styleLib.CreateSlider then
        return
    end

    local colors = styleLib.Colors
    local fontPath = styleLib.GetFont and styleLib:GetFont("primary") or styleLib.Font.path
    local titleSize = styleLib.GetFontSize and styleLib:GetFontSize("title") or styleLib.Font.title
    local normalSize = styleLib.GetFontSize and styleLib:GetFontSize("normal") or styleLib.Font.normal
    local smallSize = styleLib.GetFontSize and styleLib:GetFontSize("small") or styleLib.Font.small

    local panel = styleLib.CreateSettingsPanel(
        "RaidHelper",
        "DDingUI RaidHelper",
        GetAddonVersion(),
        { width = 760, height = 540, minWidth = 700, minHeight = 500, menuWidth = 168 }
    )
    if not panel or not panel.frame or not panel.contentChild then return end

    local frame = panel.frame
    panel.contentChild:SetHeight(490)

    if panel.titleBar then
        local logo = panel.titleBar:CreateTexture(nil, "ARTWORK")
        logo:SetSize(22, 22)
        logo:SetPoint("LEFT", panel.titleBar, "LEFT", 8, -1)
        logo:SetTexture(BRAND_ICON)
        logo:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        panel.titleBar.brandLogo = logo

        if panel.titleBar.titleText then
            panel.titleBar.titleText:ClearAllPoints()
            panel.titleBar.titleText:SetPoint("LEFT", logo, "RIGHT", 6, 0)
        end
    end

    self.pages = {
        timeline = self:CreateTimelinePage(panel.contentChild, styleLib, fontPath, titleSize, normalSize, smallSize, colors),
        cooldowns = self:CreateCooldownPage(panel.contentChild, styleLib, fontPath, titleSize, normalSize, smallSize, colors),
        profile = self:CreateProfilePage(panel.contentChild, styleLib, fontPath, titleSize, normalSize, smallSize, colors),
        data = self:CreateDataPage(panel.contentChild, styleLib, fontPath, titleSize, normalSize, smallSize, colors),
    }

    local menuData = {
        { key = "timeline", text = "타임라인", desc = "표시 옵션과 빠른 실행" },
        { key = "cooldowns", text = "쿨기 표시", desc = "주요·세미·외생기 선택" },
        { key = "profile", text = "전문화 프로필", desc = "2차 스탯과 대표 특성" },
        { key = "data", text = "데이터 팩", desc = "설치된 로그 데이터 상태" },
    }
    local tree = styleLib.CreateTreeMenu(panel.treeFrame, "RaidHelper", menuData, {
        defaultKey = "timeline",
        onSelect = function(key) Options:SelectPage(key) end,
    })

    frame:HookScript("OnHide", function()
        local ui = ns.TimelineUI
        if ui and ui:IsPreviewMode() and not ui:IsEditSessionActive() then
            ui:SetPreviewMode(false, { noReopen = true })
        end
    end)
    frame:SetScript("OnShow", function()
        Options:RefreshAll()
    end)

    self.panel = panel
    self.frame = frame
    self.tree = tree
    self.contentScroll = panel.contentScroll
    self.contentChild = panel.contentChild
    self.independentWindow = true
    self.initialized = true

    self:SelectPage("timeline")
end
