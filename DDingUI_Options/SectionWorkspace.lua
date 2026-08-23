local _, ns = ...
local DDingUI = ns.Addon
local GUI = DDingUI.GUI
local Base = DDingUI.GUIBase
local L = Base.L
local FLAT = Base.FLAT
local LSM = LibStub("LibSharedMedia-3.0", true)

local WORKSPACE_META = {
    general = {
        title = "General Settings",
        fallback = "기본 설정",
        subtitle = "Environment and profiles",
        subtitleFallback = "환경 및 프로필",
    },
    resourceBars = {
        title = "Resource Bars",
        fallback = "자원 바",
        subtitle = "Primary and secondary resources",
        subtitleFallback = "주 자원 및 보조 자원",
    },
    castBars = {
        title = "Cast Bars",
        fallback = "시전 바",
        subtitle = "Cast display and timing",
        subtitleFallback = "시전 표시 및 타이밍",
    },
    buffBar = {
        title = "Tracked Bars",
        fallback = "추적중인 막대",
        subtitle = "Tracked effect bars",
        subtitleFallback = "추적 효과 막대",
    },
}

local function T(key, fallback)
    return rawget(L, key) or fallback or key
end

local function ResolveText(value, fallback)
    if type(value) == "function" then
        local ok, result = pcall(value)
        if ok and result ~= nil then return tostring(result) end
        return fallback or ""
    end
    if value == nil then return fallback or "" end
    return tostring(value)
end

local function FontPath()
    return DDingUI.GetGlobalFont and DDingUI:GetGlobalFont() or "Fonts\\2002.TTF"
end

local function SetSurface(frame, background, border)
    frame:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    frame:SetBackdropColor(background[1], background[2], background[3], background[4] or 1)
    frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

local function CreateText(parent, size, color, justify)
    local text = parent:CreateFontString(nil, "OVERLAY")
    text:SetFont(FontPath(), math.max(1, tonumber(size) or 11), "")
    text:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    text:SetJustifyH(justify or "LEFT")
    return text
end

local function CreateDivider(parent, point, relative, relativePoint, x, y)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetPoint(point, relative, relativePoint, x, y)
    line:SetPoint(point == "TOPLEFT" and "TOPRIGHT" or "BOTTOMRIGHT", relative,
        point == "TOPLEFT" and "TOPRIGHT" or "BOTTOMRIGHT", -x, y)
    line:SetHeight(1)
    line:SetColorTexture(0.18, 0.19, 0.22, 0.8)
    return line
end

local function Clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    return math.max(minimum, math.min(maximum, value))
end

local function ColorValues(value, fallback)
    value = type(value) == "table" and value or fallback
    return tonumber(value[1]) or fallback[1], tonumber(value[2]) or fallback[2],
        tonumber(value[3]) or fallback[3], tonumber(value[4]) or fallback[4] or 1
end

local function FetchMedia(kind, name, fallback)
    if LSM and name then
        local ok, path = pcall(LSM.Fetch, LSM, kind, name, true)
        if ok and path then return path end
    end
    return fallback
end

local function ResolveFont(name)
    if name and DDingUI.GetFont then
        local ok, path = pcall(DDingUI.GetFont, DDingUI, name)
        if ok and path then return path end
    end
    return FetchMedia("font", name, FontPath())
end

local function ApplyTextStyle(text, fontName, size, color)
    text:SetFont(ResolveFont(fontName), Clamp(size or 11, 7, 28), "")
    if color then
        local r, g, b, a = ColorValues(color, { 1, 1, 1, 1 })
        text:SetTextColor(r, g, b, a)
    end
end

local function AnchorText(text, parent, point, offsetX, offsetY)
    point = type(point) == "string" and point or "CENTER"
    text:ClearAllPoints()
    text:SetPoint(point, parent, point, tonumber(offsetX) or 0, tonumber(offsetY) or 0)
    if point:find("LEFT", 1, true) then
        text:SetJustifyH("LEFT")
    elseif point:find("RIGHT", 1, true) then
        text:SetJustifyH("RIGHT")
    else
        text:SetJustifyH("CENTER")
    end
end

local function SetBarAppearance(bar, config, fallbackColor)
    local texture = FetchMedia("statusbar", config and config.texture, FLAT)
    bar:SetStatusBarTexture(texture or FLAT)
    local r, g, b, a = ColorValues(config and (config.color or config.barColor), fallbackColor)
    bar:SetStatusBarColor(r, g, b, a)
    local br, bg, bb, ba = ColorValues(config and config.bgColor, { 0.08, 0.085, 0.1, 1 })
    bar:SetBackdropColor(br, bg, bb, ba)
    local rr, rg, rb, ra = ColorValues(config and config.borderColor, { 0, 0, 0, 1 })
    bar:SetBackdropBorderColor(rr, rg, rb, ra)
end

local function CreatePreviewBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent, "BackdropTemplate")
    SetSurface(bar, { 0.08, 0.085, 0.1, 1 }, { 0, 0, 0, 1 })
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(72)
    bar.leftText = CreateText(bar, 11, { 0.96, 0.97, 0.99, 1 }, "LEFT")
    bar.leftText:SetPoint("LEFT", bar, "LEFT", 6, 0)
    bar.rightText = CreateText(bar, 11, { 0.96, 0.97, 0.99, 1 }, "RIGHT")
    bar.rightText:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
    return bar
end

local function GetClassColor()
    local _, class = UnitClass("player")
    local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if color then return color.r, color.g, color.b, 1 end
    return 1, 0.55, 0.12, 1
end

local function GetResourceColor(secondary)
    local profile = DDingUI.db and DDingUI.db.profile or {}
    local colors = profile.powerTypeColors or {}
    if colors.useClassColor then return GetClassColor() end
    local resource
    if secondary and DDingUI.ResourceBars and DDingUI.ResourceBars.GetSecondaryResource then
        local ok, result = pcall(DDingUI.ResourceBars.GetSecondaryResource)
        if ok then resource = result end
    else
        local ok, result = pcall(UnitPowerType, "player")
        if ok then resource = result end
    end
    local color = colors.colors and colors.colors[resource]
    if color then return ColorValues(color, { 0.2, 0.64, 1, 1 }) end
    return secondary and 0.2 or 0.22, secondary and 0.64 or 0.58, 1, 1
end

local function CreateGeneralPreview(parent)
    local visual = CreateFrame("Frame", nil, parent)
    visual:SetSize(650, 64)
    visual:SetPoint("CENTER", parent, "CENTER", 0, -12)
    visual.columns = {}
    local labels = {
        { "Current Profile", "현재 프로필" },
        { "UI Scale", "UI 스케일" },
        { "Display", "표시" },
    }
    for index, label in ipairs(labels) do
        local column = CreateFrame("Frame", nil, visual)
        column:SetPoint("TOPLEFT", visual, "TOPLEFT", (index - 1) * 216, 0)
        column:SetSize(216, 64)
        column.label = CreateText(column, 9, { 0.46, 0.49, 0.56, 1 })
        column.label:SetPoint("TOP", column, "TOP", 0, -5)
        column.label:SetText(T(label[1], label[2]))
        column.value = CreateText(column, 15, { 0.96, 0.97, 0.99, 1 }, "CENTER")
        column.value:SetPoint("TOP", column.label, "BOTTOM", 0, -9)
        if index < #labels then
            local divider = column:CreateTexture(nil, "ARTWORK")
            divider:SetPoint("TOPRIGHT", column, "TOPRIGHT", 0, -4)
            divider:SetPoint("BOTTOMRIGHT", column, "BOTTOMRIGHT", 0, 4)
            divider:SetWidth(1)
            divider:SetColorTexture(0.18, 0.19, 0.22, 0.85)
        end
        visual.columns[index] = column
    end

    function visual:Refresh()
        local profile = DDingUI.db and DDingUI.db.profile
        local general = profile and profile.general or {}
        local profileName = DDingUI.db and DDingUI.db.GetCurrentProfile and DDingUI.db:GetCurrentProfile() or "-"
        local scale = tonumber(general.uiScale) or (UIParent and UIParent:GetScale()) or 1
        local hiddenCount = 0
        if general.hideWhileFlying then hiddenCount = hiddenCount + 1 end
        if general.hideWhileMounted then hiddenCount = hiddenCount + 1 end
        if general.hideInVehicle then hiddenCount = hiddenCount + 1 end
        self.columns[1].value:SetText(profileName)
        self.columns[2].value:SetText(string.format("%.2f", scale))
        self.columns[3].value:SetText(hiddenCount > 0
            and string.format(T("%d rules", "%d개 조건"), hiddenCount)
            or T("Always visible", "항상 표시"))
    end
    return visual
end

local function CreateResourcePreview(parent)
    local visual = CreateFrame("Frame", nil, parent)
    visual:SetSize(660, 90)
    visual:SetPoint("CENTER", parent, "CENTER", 0, -12)
    visual.primary = CreatePreviewBar(visual)
    visual.secondary = CreatePreviewBar(visual)
    visual.primaryCaption = CreateText(visual, 9, { 0.48, 0.51, 0.58, 1 }, "RIGHT")
    visual.primaryCaption:SetText(T("Primary Resource", "주 자원"))
    visual.secondaryCaption = CreateText(visual, 9, { 0.48, 0.51, 0.58, 1 }, "RIGHT")
    visual.secondaryCaption:SetText(T("Secondary Resource", "보조 자원"))
    visual.primary:SetValue(74)
    visual.secondary:SetValue(62)
    visual.ticks = {}
    for index = 1, 4 do
        local tick = visual.secondary:CreateTexture(nil, "OVERLAY")
        tick:SetWidth(1)
        tick:SetColorTexture(0, 0, 0, 0.72)
        visual.ticks[index] = tick
    end

    function visual:Refresh(selectedKey)
        local profile = DDingUI.db and DDingUI.db.profile or {}
        local primary = profile.powerBar or {}
        local secondary = profile.secondaryPowerBar or {}
        local primaryWidth = primary.width and primary.width > 0 and primary.width or 430
        local secondaryWidth = secondary.width and secondary.width > 0 and secondary.width or primaryWidth
        primaryWidth = Clamp(primaryWidth, 220, 520)
        secondaryWidth = Clamp(secondaryWidth, 220, 520)
        local primaryHeight = Clamp(primary.height or 14, 8, 30)
        local secondaryHeight = Clamp(secondary.height or 14, 8, 30)

        self.primary:ClearAllPoints()
        self.primary:SetPoint("TOP", self, "TOP", 36, -10)
        self.primary:SetSize(primaryWidth, primaryHeight)
        self.secondary:ClearAllPoints()
        self.secondary:SetPoint("TOP", self.primary, "BOTTOM", 0, -8)
        self.secondary:SetSize(secondaryWidth, secondaryHeight)
        self.primaryCaption:ClearAllPoints()
        self.primaryCaption:SetPoint("RIGHT", self.primary, "LEFT", -10, 0)
        self.secondaryCaption:ClearAllPoints()
        self.secondaryCaption:SetPoint("RIGHT", self.secondary, "LEFT", -10, 0)

        SetBarAppearance(self.primary, primary, { GetResourceColor(false) })
        SetBarAppearance(self.secondary, secondary, { GetResourceColor(true) })
        self.primary:SetAlpha(primary.enabled == false and 0.35 or 1)
        self.secondary:SetAlpha(secondary.enabled == false and 0.35 or 1)
        self.primary.leftText:SetShown(primary.showText ~= false)
        self.primary.rightText:Hide()
        self.secondary.leftText:SetShown(secondary.showText ~= false)
        self.secondary.rightText:Hide()
        self.primary.leftText:SetText("74%")
        self.secondary.leftText:SetText("3 / 5")
        ApplyTextStyle(self.primary.leftText, primary.textFont, primary.textSize)
        ApplyTextStyle(self.secondary.leftText, secondary.textFont, secondary.textSize)
        AnchorText(self.primary.leftText, self.primary, "CENTER", primary.textX, primary.textY)
        AnchorText(self.secondary.leftText, self.secondary, "CENTER", secondary.textX, secondary.textY)

        local showTicks = secondary.showTicks ~= false
        for index, tick in ipairs(self.ticks) do
            tick:ClearAllPoints()
            tick:SetPoint("TOP", self.secondary, "TOPLEFT", secondaryWidth * index / 5, 0)
            tick:SetPoint("BOTTOM", self.secondary, "BOTTOMLEFT", secondaryWidth * index / 5, 0)
            tick:SetShown(showTicks)
        end
        local primarySelected = selectedKey and selectedKey:match("primary$")
        local secondarySelected = selectedKey and selectedKey:match("secondary$")
        self.primaryCaption:SetTextColor(primarySelected and 1 or 0.48, primarySelected and 0.48 or 0.51, primarySelected and 0.12 or 0.58, 1)
        self.secondaryCaption:SetTextColor(secondarySelected and 1 or 0.48, secondarySelected and 0.48 or 0.51, secondarySelected and 0.12 or 0.58, 1)
    end
    return visual
end

local function CreateCastPreview(parent)
    local visual = CreateFrame("Frame", nil, parent)
    visual:SetSize(680, 86)
    visual:SetPoint("CENTER", parent, "CENTER", 0, -12)
    visual.bar = CreatePreviewBar(visual)
    visual.bar:SetValue(63)
    visual.iconFrame = CreateFrame("Frame", nil, visual, "BackdropTemplate")
    SetSurface(visual.iconFrame, { 0.02, 0.02, 0.025, 1 }, { 0, 0, 0, 1 })
    visual.icon = visual.iconFrame:CreateTexture(nil, "ARTWORK")
    visual.icon:SetPoint("TOPLEFT", 1, -1)
    visual.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    visual.icon:SetTexture(136243)
    visual.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    visual.spark = visual.bar:CreateTexture(nil, "OVERLAY")
    visual.spark:SetWidth(2)
    visual.spark:SetColorTexture(1, 1, 1, 0.9)
    visual.ticks = {}
    for index = 1, 4 do
        local tick = visual.bar:CreateTexture(nil, "OVERLAY")
        tick:SetWidth(1)
        visual.ticks[index] = tick
    end

    function visual:Refresh(selectedKey)
        local profile = DDingUI.db and DDingUI.db.profile or {}
        local config = profile.castBar or {}
        local width = Clamp(config.width and config.width > 0 and config.width or 440, 240, 610)
        local height = Clamp(config.height or 24, 12, 42)
        local iconShown = config.showIcon ~= false
        self.bar:ClearAllPoints()
        self.bar:SetPoint("CENTER", self, "CENTER", iconShown and height * 0.52 or 0, -3)
        self.bar:SetSize(width, height)
        self.iconFrame:ClearAllPoints()
        self.iconFrame:SetPoint("RIGHT", self.bar, "LEFT", -3, 0)
        self.iconFrame:SetSize(height, height)
        self.iconFrame:SetShown(iconShown)
        SetBarAppearance(self.bar, config, { GetClassColor() })
        self.bar:SetAlpha(config.enabled == false and 0.35 or 1)
        self.bar.leftText:SetText(T("Preview Cast", "시전 미리보기"))
        self.bar.leftText:SetShown(config.showSpellText ~= false)
        self.bar.rightText:SetText("1.8 / 3.0")
        self.bar.rightText:SetShown(config.showTimeText ~= false)
        ApplyTextStyle(self.bar.leftText, config.spellTextFont or config.textFont, config.spellTextSize or config.textSize)
        ApplyTextStyle(self.bar.rightText, config.timeTextFont or config.textFont, config.timeTextSize or config.textSize)
        AnchorText(self.bar.leftText, self.bar, "LEFT", config.spellTextOffsetX or 4, config.spellTextOffsetY)
        AnchorText(self.bar.rightText, self.bar, "RIGHT", config.timeTextOffsetX or -4, config.timeTextOffsetY)
        self.spark:ClearAllPoints()
        self.spark:SetPoint("TOP", self.bar, "TOPLEFT", width * 0.63, 0)
        self.spark:SetPoint("BOTTOM", self.bar, "BOTTOMLEFT", width * 0.63, 0)
        self.spark:SetShown(config.showSpark ~= false)
        local showTicks = config.showChannelTicks ~= false and config.showChannelTickMarks ~= false
        for index, tick in ipairs(self.ticks) do
            tick:ClearAllPoints()
            tick:SetPoint("TOP", self.bar, "TOPLEFT", width * index / 5, 0)
            tick:SetPoint("BOTTOM", self.bar, "BOTTOMLEFT", width * index / 5, 0)
            local tr, tg, tb, ta = ColorValues(config.channelTickColor, { 1, 1, 1, 0.7 })
            tick:SetColorTexture(tr, tg, tb, ta)
            tick:SetShown(showTicks)
        end
        local highlightTicks = selectedKey and (selectedKey:match("channelTicks$") or selectedKey:match("empowered$"))
        self.bar.leftText:SetTextColor(highlightTicks and 1 or 0.96, highlightTicks and 0.48 or 0.97, highlightTicks and 0.12 or 0.99, 1)
    end
    return visual
end

local function CreateTrackedPreview(parent)
    local visual = CreateFrame("Frame", nil, parent)
    visual:SetSize(680, 92)
    visual:SetPoint("CENTER", parent, "CENTER", 0, -12)
    visual.rows = {}
    for index = 1, 2 do
        local row = CreateFrame("Frame", nil, visual)
        row.bar = CreatePreviewBar(row)
        row.iconFrame = CreateFrame("Frame", nil, row, "BackdropTemplate")
        SetSurface(row.iconFrame, { 0.02, 0.02, 0.025, 1 }, { 0, 0, 0, 1 })
        row.icon = row.iconFrame:CreateTexture(nil, "ARTWORK")
        row.icon:SetPoint("TOPLEFT", 1, -1)
        row.icon:SetPoint("BOTTOMRIGHT", -1, 1)
        row.icon:SetTexture(index == 1 and 136243 or 135953)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.count = CreateText(row.iconFrame, 10, { 1, 1, 1, 1 }, "RIGHT")
        row.count:SetPoint("BOTTOMRIGHT", row.iconFrame, "BOTTOMRIGHT", -2, 2)
        row.count:SetText(index == 1 and "2" or "")
        row.bar:SetValue(index == 1 and 76 or 43)
        visual.rows[index] = row
    end

    function visual:Refresh()
        local profile = DDingUI.db and DDingUI.db.profile or {}
        local config = profile.buffBarViewer or {}
        local width = Clamp(config.width and config.width > 0 and config.width or 430, 230, 610)
        local height = Clamp(config.height or 16, 10, 34)
        local showIcon = config.hideIcon ~= true
        local iconRight = config.iconPosition == "RIGHT"
        local spacing = Clamp(config.barSpacing or 2, 0, 12)
        for index, row in ipairs(self.rows) do
            row:SetSize(width + (showIcon and height + 4 or 0), height)
            row:ClearAllPoints()
            row:SetPoint("TOP", self, "TOP", 0, -8 - (index - 1) * (height + spacing))
            row.bar:ClearAllPoints()
            row.bar:SetSize(width, height)
            if showIcon then
                row.iconFrame:SetSize(height, height)
                row.iconFrame:ClearAllPoints()
                if iconRight then
                    row.bar:SetPoint("LEFT", row, "LEFT", 0, 0)
                    row.iconFrame:SetPoint("LEFT", row.bar, "RIGHT", config.iconGap or 0, 0)
                else
                    row.iconFrame:SetPoint("LEFT", row, "LEFT", 0, 0)
                    row.bar:SetPoint("LEFT", row.iconFrame, "RIGHT", config.iconGap or 0, 0)
                end
            else
                row.bar:SetPoint("CENTER", row, "CENTER", 0, 0)
            end
            row.iconFrame:SetShown(showIcon)
            local zoom = Clamp(config.iconZoom or 0.08, 0, 0.45)
            row.icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
            SetBarAppearance(row.bar, config, { 0.88, 0.73, 0.18, 1 })
            row.bar.leftText:SetText(index == 1 and T("Tracked Effect", "추적 효과") or T("Secondary Effect", "보조 효과"))
            row.bar.leftText:SetShown(config.showName ~= false)
            row.bar.rightText:SetText(index == 1 and "8.3" or "4.7")
            row.bar.rightText:SetShown(config.showDuration ~= false)
            row.count:SetShown(config.showApplications ~= false)
            ApplyTextStyle(row.bar.leftText, config.nameFont, config.nameSize, config.nameColor)
            ApplyTextStyle(row.bar.rightText, config.durationFont, config.durationSize, config.durationColor)
            ApplyTextStyle(row.count, config.applicationsFont, config.applicationsSize, config.applicationsColor)
            AnchorText(row.bar.leftText, row.bar, config.nameAnchor or "LEFT", config.nameOffsetX, config.nameOffsetY)
            AnchorText(row.bar.rightText, row.bar, config.durationAnchor or "RIGHT", config.durationOffsetX, config.durationOffsetY)
            AnchorText(row.count, row.iconFrame, config.applicationsAnchor or "BOTTOMRIGHT", config.applicationsOffsetX, config.applicationsOffsetY)
        end
        self:SetAlpha(config.enabled == false and 0.35 or 1)
    end
    return visual
end

local PREVIEW_BUILDERS = {
    general = CreateGeneralPreview,
    resourceBars = CreateResourcePreview,
    castBars = CreateCastPreview,
    buffBar = CreateTrackedPreview,
}

local function IsVisible(option)
    if type(option) ~= "table" then return false end
    if type(option.hidden) == "function" then
        local ok, hidden = pcall(option.hidden)
        return not (ok and hidden)
    end
    return option.hidden ~= true
end

local function SortedGroups(args)
    local groups = {}
    for key, option in pairs(args or {}) do
        if option.type == "group" and IsVisible(option) then
            groups[#groups + 1] = { key = key, option = option, order = tonumber(option.order) or 999 }
        end
    end
    table.sort(groups, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return tostring(a.key) < tostring(b.key)
    end)
    return groups
end

local function CopyPath(path, tail)
    local result = {}
    for index, value in ipairs(path or {}) do result[index] = value end
    if tail then result[#result + 1] = tail end
    return result
end

local function AppendLeafEntries(entries, item, path, parentLabel, depth)
    local option = item.option
    local label = ResolveText(option.name, item.key)
    local itemPath = CopyPath(path, item.key)
    if option.childGroups == "tab" then
        entries[#entries + 1] = {
            key = "__section." .. table.concat(itemPath, "."),
            label = label,
            isHeader = true,
            depth = depth,
        }
        for _, child in ipairs(SortedGroups(option.args)) do
            AppendLeafEntries(entries, child, itemPath, label, depth + 1)
        end
        return
    end
    entries[#entries + 1] = {
        key = table.concat(itemPath, "."),
        label = label,
        parentLabel = parentLabel,
        option = option,
        path = itemPath,
        depth = depth,
    }
end

local function BuildEntries(options)
    local entries = {}
    for _, item in ipairs(SortedGroups(options.args)) do
        AppendLeafEntries(entries, item, {}, nil, 0)
    end
    return entries
end

local function FindEntry(entries, key)
    for _, entry in ipairs(entries) do
        if not entry.isHeader and entry.key == key then return entry end
    end
end

local function FirstEntry(entries)
    for _, entry in ipairs(entries) do
        if not entry.isHeader then return entry end
    end
end

local function BuildRenderPage(entry)
    local source = entry and entry.option
    if type(source) ~= "table" or type(source.args) ~= "table" then return source end
    local firstKey, firstOrder
    for key, option in pairs(source.args) do
        if IsVisible(option) then
            local order = tonumber(option.order) or 999
            if not firstOrder or order < firstOrder then
                firstKey, firstOrder = key, order
            end
        end
    end
    if not firstKey or source.args[firstKey].type ~= "header" then return source end
    local page = {}
    for key, value in pairs(source) do page[key] = value end
    page.args = {}
    for key, value in pairs(source.args) do
        if key ~= firstKey then page.args[key] = value end
    end
    return page
end

local function AddSignatureColor(parts, color)
    if type(color) ~= "table" then
        parts[#parts + 1] = "-"
        return
    end
    for index = 1, 4 do parts[#parts + 1] = tostring(color[index] or "") end
end

local function PreviewSignature(kind, selectedKey)
    local profile = DDingUI.db and DDingUI.db.profile or {}
    local parts = { kind or "", selectedKey or "" }
    if kind == "general" then
        local config = profile.general or {}
        parts[#parts + 1] = tostring(config.uiScale or "")
        parts[#parts + 1] = tostring(config.hideWhileFlying)
        parts[#parts + 1] = tostring(config.hideWhileMounted)
        parts[#parts + 1] = tostring(config.hideInVehicle)
        parts[#parts + 1] = DDingUI.db and DDingUI.db.GetCurrentProfile and tostring(DDingUI.db:GetCurrentProfile()) or ""
    elseif kind == "resourceBars" then
        local colorSettings = profile.powerTypeColors or {}
        parts[#parts + 1] = tostring(colorSettings.useClassColor)
        local primaryR, primaryG, primaryB, primaryA = GetResourceColor(false)
        local secondaryR, secondaryG, secondaryB, secondaryA = GetResourceColor(true)
        parts[#parts + 1] = string.format("%.3f,%.3f,%.3f,%.3f", primaryR, primaryG, primaryB, primaryA)
        parts[#parts + 1] = string.format("%.3f,%.3f,%.3f,%.3f", secondaryR, secondaryG, secondaryB, secondaryA)
        for _, config in ipairs({ profile.powerBar or {}, profile.secondaryPowerBar or {} }) do
            for _, key in ipairs({ "enabled", "width", "height", "texture", "textFont", "textSize", "textX", "textY", "showText", "showTicks" }) do
                parts[#parts + 1] = tostring(config[key])
            end
            AddSignatureColor(parts, config.color or config.barColor)
            AddSignatureColor(parts, config.bgColor)
            AddSignatureColor(parts, config.borderColor)
        end
    elseif kind == "castBars" then
        local config = profile.castBar or {}
        for _, key in ipairs({ "enabled", "width", "height", "texture", "showIcon", "showSpark", "showSpellText", "spellTextFont", "spellTextSize", "spellTextOffsetX", "spellTextOffsetY", "showTimeText", "timeTextFont", "timeTextSize", "timeTextOffsetX", "timeTextOffsetY", "showChannelTicks", "showChannelTickMarks" }) do
            parts[#parts + 1] = tostring(config[key])
        end
        AddSignatureColor(parts, config.color)
        AddSignatureColor(parts, config.bgColor)
        AddSignatureColor(parts, config.channelTickColor)
    elseif kind == "buffBar" then
        local config = profile.buffBarViewer or {}
        for _, key in ipairs({ "enabled", "width", "height", "barSpacing", "texture", "hideIcon", "iconPosition", "iconGap", "iconZoom", "showName", "nameFont", "nameSize", "nameAnchor", "nameOffsetX", "nameOffsetY", "showDuration", "durationFont", "durationSize", "durationAnchor", "durationOffsetX", "durationOffsetY", "showApplications", "applicationsFont", "applicationsSize", "applicationsAnchor", "applicationsOffsetX", "applicationsOffsetY" }) do
            parts[#parts + 1] = tostring(config[key])
        end
        AddSignatureColor(parts, config.barColor)
        AddSignatureColor(parts, config.bgColor)
        AddSignatureColor(parts, config.borderColor)
        AddSignatureColor(parts, config.nameColor)
        AddSignatureColor(parts, config.durationColor)
        AddSignatureColor(parts, config.applicationsColor)
    end
    return table.concat(parts, "|")
end

local function CreateNavigationRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:RegisterForClicks("LeftButtonUp")
    row.background = row:CreateTexture(nil, "BACKGROUND")
    row.background:SetAllPoints()
    row.active = row:CreateTexture(nil, "ARTWORK")
    row.active:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.active:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.active:SetWidth(3)
    row.active:SetColorTexture(1, 0.36, 0.06, 1)
    row.index = CreateText(row, 9, { 0.38, 0.41, 0.47, 1 }, "RIGHT")
    row.index:SetWidth(22)
    row.label = CreateText(row, 11, { 0.78, 0.8, 0.85, 1 })
    row.label:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    row:SetScript("OnEnter", function(self)
        if self._isHeader or self._selected then return end
        self.background:SetColorTexture(0.085, 0.09, 0.105, 0.9)
        self.label:SetTextColor(0.96, 0.97, 0.99, 1)
    end)
    row:SetScript("OnLeave", function(self)
        if self._workspace then self._workspace:RefreshNavigationState() end
    end)
    return row
end

function GUI.CreateSectionWorkspace(contentFrame, parentFrame, options, path)
    local contentArea = parentFrame.contentArea
    parentFrame.scrollFrame:Hide()
    if parentFrame.scrollBar then parentFrame.scrollBar:Hide() end

    local old = contentArea._sectionWorkspace
    if old then
        if old.Release then old:Release() end
        old:Hide()
        old:SetParent(nil)
    end

    local kind = options.workspaceKind or (path and path[1]) or "general"
    local meta = WORKSPACE_META[kind] or WORKSPACE_META.general
    local workspace = CreateFrame("Frame", nil, contentArea, "BackdropTemplate")
    workspace:SetAllPoints(contentArea)
    workspace:SetFrameStrata("DIALOG")
    workspace:SetFrameLevel(contentArea:GetFrameLevel() + 5)
    SetSurface(workspace, { 0.025, 0.027, 0.032, 1 }, { 0.12, 0.13, 0.15, 1 })
    contentArea._sectionWorkspace = workspace
    workspace._parentFrame = parentFrame
    workspace._rootOptions = options
    workspace._rootPath = path or { kind }
    workspace.kind = kind

    local preview = CreateFrame("Frame", nil, workspace, "BackdropTemplate")
    preview:SetPoint("TOPLEFT", workspace, "TOPLEFT", 10, -10)
    preview:SetPoint("TOPRIGHT", workspace, "TOPRIGHT", -10, -10)
    preview:SetHeight(154)
    SetSurface(preview, { 0.018, 0.02, 0.024, 1 }, { 0.15, 0.16, 0.19, 1 })
    preview.title = CreateText(preview, 14, { 0.96, 0.97, 0.99, 1 })
    preview.title:SetPoint("TOPLEFT", preview, "TOPLEFT", 14, -11)
    preview.title:SetText(T(meta.title, meta.fallback))
    preview.subtitle = CreateText(preview, 10, { 0.48, 0.51, 0.58, 1 })
    preview.subtitle:SetPoint("TOPLEFT", preview.title, "BOTTOMLEFT", 0, -5)
    preview.subtitle:SetText(T(meta.subtitle, meta.subtitleFallback))
    preview.badge = CreateText(preview, 9, { 0.34, 0.9, 0.48, 1 }, "RIGHT")
    preview.badge:SetPoint("TOPRIGHT", preview, "TOPRIGHT", -14, -15)
    preview.badge:SetText(T("Live Preview", "실시간 미리보기"))
    CreateDivider(preview, "TOPLEFT", preview, "TOPLEFT", 12, -47)

    local lower = CreateFrame("Frame", nil, workspace)
    lower:SetPoint("TOPLEFT", preview, "BOTTOMLEFT", 0, -8)
    lower:SetPoint("BOTTOMRIGHT", workspace, "BOTTOMRIGHT", -10, 10)

    local navigation = CreateFrame("Frame", nil, lower, "BackdropTemplate")
    navigation:SetPoint("TOPLEFT", lower, "TOPLEFT", 0, 0)
    navigation:SetPoint("BOTTOMLEFT", lower, "BOTTOMLEFT", 0, 0)
    navigation:SetWidth(190)
    SetSurface(navigation, { 0.035, 0.037, 0.044, 1 }, { 0.14, 0.15, 0.18, 1 })
    navigation.title = CreateText(navigation, 9, { 0.48, 0.51, 0.58, 1 })
    navigation.title:SetPoint("TOPLEFT", navigation, "TOPLEFT", 14, -13)
    navigation.title:SetText(T("Settings Sections", "설정 영역"))
    CreateDivider(navigation, "TOPLEFT", navigation, "TOPLEFT", 10, -37)
    navigation.rows = {}

    local settings = CreateFrame("Frame", nil, lower, "BackdropTemplate")
    settings:SetPoint("TOPLEFT", navigation, "TOPRIGHT", 8, 0)
    settings:SetPoint("BOTTOMRIGHT", lower, "BOTTOMRIGHT", 0, 0)
    SetSurface(settings, { 0.032, 0.034, 0.04, 1 }, { 0.14, 0.15, 0.18, 1 })
    settings.header = CreateFrame("Frame", nil, settings)
    settings.header:SetPoint("TOPLEFT", settings, "TOPLEFT", 0, 0)
    settings.header:SetPoint("TOPRIGHT", settings, "TOPRIGHT", 0, 0)
    settings.header:SetHeight(55)
    settings.header.title = CreateText(settings.header, 13, { 0.96, 0.97, 0.99, 1 })
    settings.header.title:SetPoint("TOPLEFT", settings.header, "TOPLEFT", 14, -11)
    settings.header.breadcrumb = CreateText(settings.header, 9, { 0.48, 0.51, 0.58, 1 })
    settings.header.breadcrumb:SetPoint("TOPLEFT", settings.header.title, "BOTTOMLEFT", 0, -5)
    CreateDivider(settings.header, "BOTTOMLEFT", settings.header, "BOTTOMLEFT", 10, 0)

    local settingsScroll = CreateFrame("ScrollFrame", nil, settings)
    settingsScroll:SetPoint("TOPLEFT", settings.header, "BOTTOMLEFT", 4, -4)
    settingsScroll:SetPoint("BOTTOMRIGHT", settings, "BOTTOMRIGHT", -14, 4)
    settingsScroll:EnableMouseWheel(true)
    local settingsChild = CreateFrame("Frame", nil, settingsScroll)
    settingsChild:SetWidth(600)
    settingsChild:SetHeight(1)
    settingsChild.widgets = {}
    settingsChild.scrollFrame = settingsScroll
    settingsChild._insideSectionWorkspace = true
    settingsScroll:SetScrollChild(settingsChild)
    local settingsScrollBar = GUI.CreateCustomScrollBar(settings, settingsScroll)
    settingsScrollBar:SetPoint("TOPLEFT", settingsScroll, "TOPRIGHT", 3, 0)
    settingsScrollBar:SetPoint("BOTTOMLEFT", settingsScroll, "BOTTOMRIGHT", 3, 0)
    settingsScroll.ScrollBar = settingsScrollBar
    settingsScroll:SetScript("OnSizeChanged", function(self)
        local width = self:GetWidth()
        if width and width > 80 then settingsChild:SetWidth(width - 1) end
    end)
    settingsChild:SetScript("OnSizeChanged", function()
        if settingsScrollBar.UpdateThumbPosition then C_Timer.After(0, settingsScrollBar.UpdateThumbPosition) end
    end)

    workspace.preview = preview
    workspace.navigation = navigation
    workspace.settings = settings
    workspace.settingsScroll = settingsScroll
    workspace.settingsChild = settingsChild
    workspace.settingsScrollBar = settingsScrollBar
    workspace.previewVisual = (PREVIEW_BUILDERS[kind] or CreateGeneralPreview)(preview)

    function workspace:RefreshNavigationState()
        local selectableIndex = 0
        for _, row in ipairs(self.navigation.rows) do
            local entry = row._entry
            if entry and not entry.isHeader then selectableIndex = selectableIndex + 1 end
            row._selected = entry and not entry.isHeader and entry.key == self.selectedKey
            row.active:SetShown(row._selected)
            if not entry or entry.isHeader then
                row.background:SetColorTexture(0, 0, 0, 0)
                row.index:SetText("")
                row.label:SetTextColor(0.48, 0.51, 0.58, 1)
            elseif row._selected then
                row.background:SetColorTexture(0.09, 0.095, 0.11, 1)
                row.index:SetText(string.format("%02d", selectableIndex))
                row.index:SetTextColor(1, 0.38, 0.08, 1)
                row.label:SetTextColor(1, 1, 1, 1)
            else
                row.background:SetColorTexture(0, 0, 0, 0)
                row.index:SetText(string.format("%02d", selectableIndex))
                row.index:SetTextColor(0.38, 0.41, 0.47, 1)
                row.label:SetTextColor(0.78, 0.8, 0.85, 1)
            end
        end
    end

    function workspace:RebuildNavigation()
        self.entries = BuildEntries(self._rootOptions)
        local y = 44
        for index, entry in ipairs(self.entries) do
            local row = self.navigation.rows[index] or CreateNavigationRow(self.navigation)
            self.navigation.rows[index] = row
            row._workspace = self
            row._entry = entry
            row._isHeader = entry.isHeader == true
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.navigation, "TOPLEFT", 0, -y)
            row:SetPoint("RIGHT", self.navigation, "RIGHT", 0, 0)
            local height = entry.isHeader and 27 or 39
            row:SetHeight(height)
            row.label:ClearAllPoints()
            if entry.isHeader then
                row.index:Hide()
                row.label:SetPoint("LEFT", row, "LEFT", 14, -2)
                row.label:SetFont(FontPath(), 9, "")
            else
                row.index:Show()
                row.index:ClearAllPoints()
                row.index:SetPoint("LEFT", row, "LEFT", 10 + (entry.depth or 0) * 8, 0)
                row.label:SetPoint("LEFT", row.index, "RIGHT", 9, 0)
                row.label:SetFont(FontPath(), 11, "")
            end
            row.label:SetText(entry.label)
            local capturedKey = entry.key
            row:SetScript("OnClick", entry.isHeader and nil or function()
                self:SelectEntry(capturedKey, false)
            end)
            row:Show()
            y = y + height
        end
        for index = #self.entries + 1, #self.navigation.rows do
            self.navigation.rows[index]:Hide()
            self.navigation.rows[index]._entry = nil
        end

        local remembered = DDingUI._sectionWorkspaceSelections and DDingUI._sectionWorkspaceSelections[self.kind]
        local requested = self._parentFrame._requestedSubTabPath
        local requestedKey = requested and table.concat(requested, ".") or nil
        self._parentFrame._requestedSubTabPath = nil
        local selected = FindEntry(self.entries, self.selectedKey)
            or FindEntry(self.entries, requestedKey)
            or FindEntry(self.entries, remembered)
        if not selected and requestedKey then
            for _, entry in ipairs(self.entries) do
                if not entry.isHeader and entry.key:sub(1, #requestedKey + 1) == requestedKey .. "." then
                    selected = entry
                    break
                end
            end
        end
        selected = selected or FirstEntry(self.entries)
        self.selectedKey = selected and selected.key or nil
        self:RefreshNavigationState()
    end

    function workspace:RefreshPreview()
        if self.previewVisual and self.previewVisual.Refresh then
            self.previewVisual:Refresh(self.selectedKey)
        end
        self._previewSignature = PreviewSignature(self.kind, self.selectedKey)
    end

    function workspace:RenderSettings(preserveScroll)
        local entry = FindEntry(self.entries, self.selectedKey)
        if not entry then return end
        local oldScroll = preserveScroll and self.settingsScroll:GetVerticalScroll() or 0
        self.settings.header.title:SetText(entry.label)
        local rootLabel = T(meta.title, meta.fallback)
        self.settings.header.breadcrumb:SetText(entry.parentLabel
            and (rootLabel .. "  /  " .. entry.parentLabel)
            or rootLabel)
        local renderPath = CopyPath(self._rootPath)
        for _, value in ipairs(entry.path or {}) do renderPath[#renderPath + 1] = value end
        GUI.RenderOptions(self.settingsChild, BuildRenderPage(entry), renderPath, self._parentFrame)
        C_Timer.After(0, function()
            if not self:IsShown() then return end
            local maximum = math.max(0, self.settingsChild:GetHeight() - self.settingsScroll:GetHeight())
            self.settingsScroll:SetVerticalScroll(math.max(0, math.min(maximum, oldScroll)))
            if self.settingsScrollBar.UpdateThumbPosition then self.settingsScrollBar.UpdateThumbPosition() end
        end)
    end

    function workspace:SelectEntry(key, preserveScroll)
        local entry = FindEntry(self.entries, key)
        if not entry then return end
        self.selectedKey = entry.key
        DDingUI._sectionWorkspaceSelections = DDingUI._sectionWorkspaceSelections or {}
        DDingUI._sectionWorkspaceSelections[self.kind] = entry.key
        self:RefreshNavigationState()
        self:RefreshPreview()
        self:RenderSettings(preserveScroll)
    end

    function workspace:RefreshAll(preserveScroll)
        local selected = self.selectedKey
        self:RebuildNavigation()
        if selected and FindEntry(self.entries, selected) then self.selectedKey = selected end
        self:RefreshNavigationState()
        self:RefreshPreview()
        self:RenderSettings(preserveScroll)
    end

    function workspace:Release()
        self:SetScript("OnUpdate", nil)
        self:SetScript("OnSizeChanged", nil)
        if self._resizeTimer then self._resizeTimer:Cancel(); self._resizeTimer = nil end
    end

    workspace:SetScript("OnUpdate", function(self, elapsed)
        self._previewElapsed = (self._previewElapsed or 0) + elapsed
        if self._previewElapsed < 0.12 then return end
        self._previewElapsed = 0
        local signature = PreviewSignature(self.kind, self.selectedKey)
        if signature ~= self._previewSignature then self:RefreshPreview() end
    end)
    workspace:SetScript("OnSizeChanged", function(self)
        if self._resizeTimer then self._resizeTimer:Cancel() end
        self._resizeTimer = C_Timer.NewTimer(0.04, function()
            self._resizeTimer = nil
            if self:IsShown() then self:RefreshPreview() end
        end)
    end)
    workspace:SetScript("OnHide", function(self) self:Release() end)
    workspace:RefreshAll(false)
end
