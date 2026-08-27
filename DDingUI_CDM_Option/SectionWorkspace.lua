local _, ns = ...
local DDingUI = ns.Addon
local GUI = DDingUI.GUI
local Base = DDingUI.GUIBase
local L = Base.L
local FLAT = Base.FLAT
local THEME = Base.THEME
local LSM = LibStub("LibSharedMedia-3.0", true)
local SL = _G.DDingUI_StyleLib

local WORKSPACE_META = {
    general = {
        title = "Dashboard",
        fallback = "대시보드",
        subtitle = "Current profile layout and status",
        subtitleFallback = "현재 프로필의 배치와 상태",
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
    line:SetColorTexture(THEME.border[1], THEME.border[2], THEME.border[3], 0.82)
    return line
end

local function Clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    return math.max(minimum, math.min(maximum, value))
end

local function ColorValues(value, fallback)
    value = type(value) == "table" and value or fallback
    return tonumber(value[1] or value.r) or fallback[1], tonumber(value[2] or value.g) or fallback[2],
        tonumber(value[3] or value.b) or fallback[3], tonumber(value[4] or value.a) or fallback[4] or 1
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

local function SetBarAppearance(bar, config, fallbackColor, resolvedColor)
    local texture = FetchMedia("statusbar", config and config.texture, FLAT)
    bar:SetStatusBarTexture(texture or FLAT)
    local color = resolvedColor or (config and (config.color or config.barColor))
    if SL and SL.ApplyBarColor then
        SL.ApplyBarColor(bar, color, fallbackColor)
    else
        local r, g, b, a = ColorValues(color, fallbackColor)
        bar:SetStatusBarColor(r, g, b, a)
    end
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

local function GetClassColorSpec()
    local r, g, b, a = GetClassColor()
    return { r, g, b, a }
end

local function GetResourceColorSpec(secondary)
    local profile = DDingUI.db and DDingUI.db.profile or {}
    local colors = profile.powerTypeColors or {}
    if colors.useClassColor then return GetClassColorSpec() end
    local resource
    if secondary and DDingUI.ResourceBars and DDingUI.ResourceBars.GetSecondaryResource then
        local ok, result = pcall(DDingUI.ResourceBars.GetSecondaryResource)
        if ok then resource = result end
    elseif not secondary and DDingUI.ResourceBars and DDingUI.ResourceBars.GetPrimaryResource then
        local ok, result = pcall(DDingUI.ResourceBars.GetPrimaryResource)
        if ok then resource = result end
    else
        local ok, result = pcall(UnitPowerType, "player")
        if ok then resource = result end
    end
    local color = colors.colors and colors.colors[resource]
    if color then return color end
    return { secondary and 0.2 or 0.22, secondary and 0.64 or 0.58, 1, 1 }
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
    visual:SetPoint("CENTER", parent, "CENTER", 0, -24)
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
        local totalHeight = primaryHeight + 8 + secondaryHeight

        self.primary:ClearAllPoints()
        self.primary:SetPoint("TOP", self, "CENTER", 36, totalHeight / 2)
        self.primary:SetSize(primaryWidth, primaryHeight)
        self.secondary:ClearAllPoints()
        self.secondary:SetPoint("TOP", self.primary, "BOTTOM", 0, -8)
        self.secondary:SetSize(secondaryWidth, secondaryHeight)
        self.primaryCaption:ClearAllPoints()
        self.primaryCaption:SetPoint("RIGHT", self.primary, "LEFT", -10, 0)
        self.secondaryCaption:ClearAllPoints()
        self.secondaryCaption:SetPoint("RIGHT", self.secondary, "LEFT", -10, 0)

        SetBarAppearance(self.primary, primary, { 0.22, 0.58, 1, 1 }, GetResourceColorSpec(false))
        SetBarAppearance(self.secondary, secondary, { 0.2, 0.64, 1, 1 }, GetResourceColorSpec(true))
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
    SetSurface(visual.iconFrame, THEME.input, THEME.border)
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
        local castColor = config.useClassColor and GetClassColorSpec() or config.color
        SetBarAppearance(self.bar, config, { 1, 0.55, 0.12, 1 }, castColor)
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
    visual:SetPoint("CENTER", parent, "CENTER", 0, -24)
    visual.rows = {}
    for index = 1, 2 do
        local row = CreateFrame("Frame", nil, visual)
        row.bar = CreatePreviewBar(row)
        row.iconFrame = CreateFrame("Frame", nil, row, "BackdropTemplate")
        SetSurface(row.iconFrame, THEME.input, THEME.border)
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
        local totalHeight = height * #self.rows + spacing * (#self.rows - 1)
        for index, row in ipairs(self.rows) do
            row:SetSize(width + (showIcon and height + 4 or 0), height)
            row:ClearAllPoints()
            row:SetPoint("TOP", self, "CENTER", 0, totalHeight / 2 - (index - 1) * (height + spacing))
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
    parts[#parts + 1] = tostring(color[1] or color.r or "")
    parts[#parts + 1] = tostring(color[2] or color.g or "")
    parts[#parts + 1] = tostring(color[3] or color.b or "")
    parts[#parts + 1] = tostring(color[4] or color.a or "")
    parts[#parts + 1] = tostring(color.gradientMode or "SOLID")
    parts[#parts + 1] = tostring(color.gradientOrientation or "HORIZONTAL")
    local gradient = type(color.gradientColor) == "table" and color.gradientColor or {}
    for index = 1, 4 do parts[#parts + 1] = tostring(gradient[index] or "") end
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
        AddSignatureColor(parts, GetResourceColorSpec(false))
        AddSignatureColor(parts, GetResourceColorSpec(true))
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
        for _, key in ipairs({ "enabled", "width", "height", "texture", "useClassColor", "showIcon", "showSpark", "showSpellText", "spellTextFont", "spellTextSize", "spellTextOffsetX", "spellTextOffsetY", "showTimeText", "timeTextFont", "timeTextSize", "timeTextOffsetX", "timeTextOffsetY", "showChannelTicks", "showChannelTickMarks" }) do
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
    row.active:SetColorTexture(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
    row.index = CreateText(row, 9, { 0.38, 0.41, 0.47, 1 }, "RIGHT")
    row.index:SetWidth(22)
    row.label = CreateText(row, 11, { 0.78, 0.8, 0.85, 1 })
    row.label:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    row:SetScript("OnEnter", function(self)
        if self._isHeader or self._selected then return end
        self.background:SetColorTexture(THEME.bgHover[1], THEME.bgHover[2], THEME.bgHover[3], 1)
        self.label:SetTextColor(0.96, 0.97, 0.99, 1)
    end)
    row:SetScript("OnLeave", function(self)
        if self._workspace then self._workspace:RefreshNavigationState() end
    end)
    return row
end

local DASHBOARD_GROUP_LABEL_KEYS = {
    Cooldowns = "Essential Cooldowns",
    Buffs = "Buff Icons",
    Utility = "Utility Cooldowns",
}
local DASHBOARD_PREVIEW_MAX_ZOOM = 2.25

local function DashboardNumber(value)
    if issecretvalue and issecretvalue(value) then return nil end
    return type(value) == "number" and value or nil
end

local function DashboardTexture(value)
    if value == nil or (issecretvalue and issecretvalue(value)) then return nil end
    local valueType = type(value)
    return (valueType == "number" or valueType == "string") and value or nil
end

local function DashboardFrameRect(frame)
    if not frame then return nil end
    local ok, left, bottom, width, height = pcall(function()
        if frame.GetRect then return frame:GetRect() end
        return frame:GetLeft(), frame:GetBottom(), frame:GetWidth(), frame:GetHeight()
    end)
    if not ok then return nil end
    left, bottom = DashboardNumber(left), DashboardNumber(bottom)
    width, height = DashboardNumber(width), DashboardNumber(height)
    if not left or not bottom or not width or not height or width <= 0 or height <= 0 then return nil end
    return { left = left, bottom = bottom, width = width, height = height }
end

local function DashboardPoint(rect, point)
    point = type(point) == "string" and point or "CENTER"
    local x = point:find("LEFT", 1, true) and rect.left
        or point:find("RIGHT", 1, true) and (rect.left + rect.width)
        or (rect.left + rect.width * 0.5)
    local y = point:find("BOTTOM", 1, true) and rect.bottom
        or point:find("TOP", 1, true) and (rect.bottom + rect.height)
        or (rect.bottom + rect.height * 0.5)
    return x, y
end

local function DashboardConfiguredRect(config, width, height, uiRect)
    config = type(config) == "table" and config or {}
    width = math.max(1, tonumber(width) or 160)
    height = math.max(1, tonumber(height) or 18)
    local anchorFrame = type(config.attachTo) == "string" and _G[config.attachTo] or nil
    local anchorRect = DashboardFrameRect(anchorFrame) or uiRect
    if not anchorRect then return nil end
    local anchorX, anchorY = DashboardPoint(anchorRect, config.anchorPoint)
    local ownRect = { left = 0, bottom = 0, width = width, height = height }
    local ownX, ownY = DashboardPoint(ownRect, config.selfPoint)
    return {
        left = anchorX + (tonumber(config.offsetX) or 0) - ownX,
        bottom = anchorY + (tonumber(config.offsetY) or 0) - ownY,
        width = width,
        height = height,
    }
end

local function DashboardViewportRect(rects, uiRect)
    local left, right, bottom, top
    for _, rect in pairs(rects) do
        left = left and math.min(left, rect.left) or rect.left
        right = right and math.max(right, rect.left + rect.width) or (rect.left + rect.width)
        bottom = bottom and math.min(bottom, rect.bottom) or rect.bottom
        top = top and math.max(top, rect.bottom + rect.height) or (rect.bottom + rect.height)
    end
    if not left then
        return {
            left = uiRect.left,
            bottom = uiRect.bottom,
            width = uiRect.width,
            height = uiRect.height,
            zoom = 1,
        }
    end

    local zoom = math.min(DASHBOARD_PREVIEW_MAX_ZOOM,
        uiRect.width * 0.84 / math.max(1, right - left),
        uiRect.height * 0.84 / math.max(1, top - bottom))
    zoom = Clamp(zoom, 1, DASHBOARD_PREVIEW_MAX_ZOOM)
    local width, height = uiRect.width / zoom, uiRect.height / zoom
    local centerX = Clamp((left + right) * 0.5,
        uiRect.left + width * 0.5, uiRect.left + uiRect.width - width * 0.5)
    local centerY = Clamp((bottom + top) * 0.5,
        uiRect.bottom + height * 0.5, uiRect.bottom + uiRect.height - height * 0.5)
    return {
        left = centerX - width * 0.5,
        bottom = centerY - height * 0.5,
        width = width,
        height = height,
        zoom = zoom,
    }
end

local function DashboardIconTexture(icon)
    if not icon then return nil end
    local ok, texture = pcall(function()
        local region = icon.Icon or icon.icon or icon.IconTexture or icon.texture
        return region and region.GetTexture and region:GetTexture() or nil
    end)
    return ok and DashboardTexture(texture) or nil
end

local function DashboardTokenTexture(token)
    local id = type(token) == "number" and token
        or type(token) == "string" and tonumber(token:match("(%d+)"))
    if not id or not C_Spell or not C_Spell.GetSpellTexture then return nil end
    local ok, texture = pcall(C_Spell.GetSpellTexture, id)
    return ok and DashboardTexture(texture) or nil
end

local function DashboardGroupTextures(frame, settings)
    local textures = {}
    local iconFrames = {}
    local managed, count
    if frame then
        pcall(function()
            managed = frame._managedIcons
            count = DashboardNumber(frame._iconCount)
        end)
    end
    if type(managed) == "table" then
        count = math.min(24, math.max(0, count or #managed))
        for index = 1, count do
            textures[#textures + 1] = DashboardIconTexture(managed[index]) or 136243
            iconFrames[index] = managed[index]
        end
    end
    if #textures == 0 and type(settings.iconOrder) == "table" then
        for index = 1, math.min(24, #settings.iconOrder) do
            textures[index] = DashboardTokenTexture(settings.iconOrder[index]) or 136243
        end
    end
    if #textures == 0 then
        for index = 1, 4 do textures[index] = 136243 end
    end
    return textures, iconFrames
end

local function DashboardGroupSize(settings, count)
    local iconHeight = math.max(8, tonumber(settings.iconSize) or 36)
    local iconWidth = iconHeight * math.max(0.5, tonumber(settings.aspectRatioCrop) or 1)
    local spacing = math.max(0, tonumber(settings.spacing) or 2)
    local limit = math.max(1, math.min(count, tonumber(settings.rowLimit) or count))
    local horizontal = settings.direction ~= "UP" and settings.direction ~= "DOWN"
    local primary = math.min(count, limit)
    local secondary = math.max(1, math.ceil(count / limit))
    if horizontal then
        return primary * iconWidth + math.max(0, primary - 1) * spacing,
            secondary * iconHeight + math.max(0, secondary - 1) * spacing
    end
    return secondary * iconWidth + math.max(0, secondary - 1) * spacing,
        primary * iconHeight + math.max(0, primary - 1) * spacing
end

local function DashboardGroupLabel(groupName, settings)
    local localeKey = DASHBOARD_GROUP_LABEL_KEYS[groupName]
    return (localeKey and T(localeKey, nil)) or settings.name or groupName
end

local function DashboardTrackedGroups()
    if not DDingUI.GetTrackedBuffGroups then return {} end
    local ok, groups = pcall(DDingUI.GetTrackedBuffGroups, DDingUI)
    return ok and type(groups) == "table" and groups or {}
end

local function BuildDashboardDescriptors()
    local profile = DDingUI.db and DDingUI.db.profile or {}
    local descriptors = {}
    local groupStore = profile.groupSystem and profile.groupSystem.groups or {}
    local groups = {}
    for groupName, settings in pairs(groupStore) do
        groups[#groups + 1] = {
            name = groupName,
            settings = settings,
            order = tonumber(settings.order) or 999,
        }
    end
    table.sort(groups, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return tostring(a.name) < tostring(b.name)
    end)
    for _, group in ipairs(groups) do
        local frame = DDingUI.GroupRenderer and DDingUI.GroupRenderer.groupFrames
            and DDingUI.GroupRenderer.groupFrames[group.name]
        local textures, iconFrames = DashboardGroupTextures(frame, group.settings)
        local width, height = DashboardGroupSize(group.settings, #textures)
        descriptors[#descriptors + 1] = {
            key = "group:" .. group.name,
            kind = "icons",
            label = DashboardGroupLabel(group.name, group.settings),
            path = (T("CDM Bars", "CDM 바")) .. "  /  " .. DashboardGroupLabel(group.name, group.settings),
            target = "groupSystem.group_" .. group.name,
            frame = frame,
            config = group.settings,
            width = width,
            height = height,
            textures = textures,
            iconFrames = iconFrames,
            enabled = group.settings.enabled ~= false,
        }
    end

    local function AddBar(key, label, target, frame, config, width, height, color)
        descriptors[#descriptors + 1] = {
            key = key,
            kind = "bar",
            label = label,
            path = label,
            target = target,
            frame = frame,
            config = config,
            width = width,
            height = height,
            color = color,
            enabled = config.enabled ~= false,
        }
    end

    local primary = profile.powerBar or {}
    AddBar("power", T("Primary Resource", "주 자원"), "resourceBars.primary", DDingUI.powerBar,
        primary, primary.width and primary.width > 0 and primary.width or 430, primary.height or 14,
        GetResourceColorSpec(false))
    local secondary = profile.secondaryPowerBar or {}
    AddBar("secondaryPower", T("Secondary Resource", "보조 자원"), "resourceBars.secondary",
        DDingUI.secondaryPowerBar, secondary,
        secondary.width and secondary.width > 0 and secondary.width or 430,
        secondary.height or 14, GetResourceColorSpec(true))
    local cast = profile.castBar or {}
    local castColor = cast.useClassColor and GetClassColorSpec() or cast.color
    AddBar("cast", T("Player Cast Bar", "플레이어 시전 바"), "castBars.general", DDingUI.castBar,
        cast, cast.width and cast.width > 0 and cast.width or 440, cast.height or 24,
        castColor or { 1, 0.55, 0.12, 1 })

    local trackedGroups = DashboardTrackedGroups()
    local trackedKeys = {}
    for key in pairs(trackedGroups) do trackedKeys[#trackedKeys + 1] = key end
    table.sort(trackedKeys, function(a, b) return tostring(a) < tostring(b) end)
    local trackedConfig = profile.buffTrackerBar or {}
    for _, key in ipairs(trackedKeys) do
        AddBar("trackedAura:" .. tostring(key), T("Buff Tracker", "커스텀 오라"), "buffTracker",
            trackedGroups[key], trackedConfig,
            trackedConfig.width and trackedConfig.width > 0 and trackedConfig.width or 320,
            math.max(12, trackedConfig.height or 16), trackedConfig.barColor or { 1, 0.8, 0, 1 })
    end

    local trackedBar = profile.buffBarViewer or {}
    AddBar("trackedBars", T("Tracked Bars", "추적중인 막대"), "buffBar",
        _G["BuffBarCooldownViewer"], trackedBar,
        trackedBar.width and trackedBar.width > 0 and trackedBar.width or 430,
        trackedBar.height or 16, trackedBar.barColor or { 0.88, 0.73, 0.18, 1 })
    return descriptors
end

local function DashboardSourceSignature()
    local profile = DDingUI.db and DDingUI.db.profile or {}
    local parts = {
        DDingUI.db and DDingUI.db.GetCurrentProfile and tostring(DDingUI.db:GetCurrentProfile()) or "",
    }
    local groups = profile.groupSystem and profile.groupSystem.groups or {}
    for name, settings in pairs(groups) do
        local frame = DDingUI.GroupRenderer and DDingUI.GroupRenderer.groupFrames
            and DDingUI.GroupRenderer.groupFrames[name]
        local count = frame and DashboardNumber(frame._iconCount) or 0
        local groupParts = {
            name,
            tostring(settings.enabled ~= false),
            tostring(count or 0),
            tostring(settings.iconSize),
            tostring(settings.aspectRatioCrop),
            tostring(settings.spacing),
            tostring(settings.rowLimit),
            tostring(settings.direction),
            tostring(settings.growDirection),
        }
        for _, texture in ipairs(DashboardGroupTextures(frame, settings)) do
            groupParts[#groupParts + 1] = tostring(texture)
        end
        parts[#parts + 1] = table.concat(groupParts, ":")
    end
    for key in pairs(DashboardTrackedGroups()) do
        parts[#parts + 1] = "tracked:" .. tostring(key)
    end
    parts[#parts + 1] = "power:" .. tostring(profile.powerBar and profile.powerBar.enabled ~= false)
    parts[#parts + 1] = "secondary:" .. tostring(profile.secondaryPowerBar and profile.secondaryPowerBar.enabled ~= false)
    parts[#parts + 1] = "cast:" .. tostring(profile.castBar and profile.castBar.enabled ~= false)
    parts[#parts + 1] = "trackedBars:" .. tostring(profile.buffBarViewer and profile.buffBarViewer.enabled ~= false)
    table.sort(parts)
    return table.concat(parts, "|")
end

local function CreateDashboardQuickRow(parent, label, target)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(43)
    row.target = target
    row.background = row:CreateTexture(nil, "BACKGROUND")
    row.background:SetAllPoints()
    row.background:SetColorTexture(0, 0, 0, 0)
    row.label = CreateText(row, 10, { 0.82, 0.84, 0.88, 1 })
    row.label:SetPoint("LEFT", row, "LEFT", 9, 0)
    row.label:SetText(label)
    row.value = CreateText(row, 9, { 0.5, 0.54, 0.6, 1 }, "RIGHT")
    row.value:SetPoint("RIGHT", row, "RIGHT", -9, 0)
    row.value:SetPoint("LEFT", row.label, "RIGHT", 8, 0)
    local divider = row:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    divider:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    divider:SetHeight(1)
    divider:SetColorTexture(THEME.border[1], THEME.border[2], THEME.border[3], 0.72)
    row:SetScript("OnEnter", function(self)
        self.background:SetColorTexture(THEME.bgHover[1], THEME.bgHover[2], THEME.bgHover[3], 1)
        self.label:SetTextColor(1, 1, 1, 1)
    end)
    row:SetScript("OnLeave", function(self)
        self.background:SetColorTexture(0, 0, 0, 0)
        self.label:SetTextColor(0.82, 0.84, 0.88, 1)
    end)
    return row
end

local function CreateDashboardWorkspace(contentFrame, parentFrame)
    local contentArea = parentFrame.contentArea
    parentFrame.scrollFrame:Hide()
    if parentFrame.scrollBar then parentFrame.scrollBar:Hide() end

    local old = contentArea._sectionWorkspace
    if old then
        if old.Release then old:Release() end
        old:Hide()
        old:SetParent(nil)
    end

    local workspace = CreateFrame("Frame", nil, contentArea, "BackdropTemplate")
    workspace:SetAllPoints(contentArea)
    workspace:SetFrameStrata("DIALOG")
    workspace:SetFrameLevel(contentArea:GetFrameLevel() + 5)
    SetSurface(workspace, THEME.shell, THEME.border)
    contentArea._sectionWorkspace = workspace
    workspace._parentFrame = parentFrame
    workspace.nodes = {}

    local header = CreateFrame("Frame", nil, workspace)
    header:SetPoint("TOPLEFT", workspace, "TOPLEFT", 10, -10)
    header:SetPoint("TOPRIGHT", workspace, "TOPRIGHT", -10, -10)
    header:SetHeight(52)
    header.title = CreateText(header, 15, { 0.96, 0.97, 0.99, 1 })
    header.title:SetPoint("TOPLEFT", header, "TOPLEFT", 4, -4)
    header.title:SetText(T("Dashboard", "대시보드"))
    header.subtitle = CreateText(header, 9, { 0.48, 0.51, 0.58, 1 })
    header.subtitle:SetPoint("TOPLEFT", header.title, "BOTTOMLEFT", 0, -5)
    header.subtitle:SetText(T("Current profile layout and status", "현재 프로필의 배치와 상태"))
    header.live = CreateText(header, 9, { 0.34, 0.9, 0.48, 1 }, "RIGHT")
    header.live:SetPoint("RIGHT", header, "RIGHT", -4, 4)
    header.live:SetText(T("Live Layout", "실시간 배치"))
    header.liveDot = header:CreateTexture(nil, "ARTWORK")
    header.liveDot:SetSize(6, 6)
    header.liveDot:SetPoint("RIGHT", header.live, "LEFT", -7, 0)
    header.liveDot:SetColorTexture(0.34, 0.9, 0.48, 1)
    CreateDivider(header, "BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)

    local body = CreateFrame("Frame", nil, workspace)
    body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
    body:SetPoint("BOTTOMRIGHT", workspace, "BOTTOMRIGHT", -10, 10)

    local quick = CreateFrame("Frame", nil, body, "BackdropTemplate")
    quick:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, 0)
    quick:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
    quick:SetWidth(250)
    SetSurface(quick, THEME.panel, THEME.border)
    quick.header = CreateText(quick, 12, { 0.96, 0.97, 0.99, 1 })
    quick.header:SetPoint("TOPLEFT", quick, "TOPLEFT", 12, -13)
    quick.header:SetText(T("Quick Settings", "빠른 설정"))
    CreateDivider(quick, "TOPLEFT", quick, "TOPLEFT", 10, -40)

    local selected = CreateFrame("Frame", nil, quick, "BackdropTemplate")
    selected:SetPoint("TOPLEFT", quick, "TOPLEFT", 10, -51)
    selected:SetPoint("TOPRIGHT", quick, "TOPRIGHT", -10, -51)
    selected:SetHeight(108)
    SetSurface(selected, THEME.input, THEME.borderLight)
    selected.eyebrow = CreateText(selected, 8, { 1, 0.43, 0.08, 1 })
    selected.eyebrow:SetPoint("TOPLEFT", selected, "TOPLEFT", 10, -9)
    selected.eyebrow:SetText(T("Selected Element", "선택한 요소"))
    selected.title = CreateText(selected, 13, { 0.96, 0.97, 0.99, 1 })
    selected.title:SetPoint("TOPLEFT", selected.eyebrow, "BOTTOMLEFT", 0, -6)
    selected.path = CreateText(selected, 8, { 0.5, 0.54, 0.6, 1 })
    selected.path:SetPoint("TOPLEFT", selected.title, "BOTTOMLEFT", 0, -5)
    selected.path:SetPoint("RIGHT", selected, "RIGHT", -10, 0)
    selected.open = GUI.CreateStyledButton(selected, T("Open Settings", "설정 열기"), 100, 26)
    selected.open:SetPoint("BOTTOMLEFT", selected, "BOTTOMLEFT", 10, 9)
    selected.open:SetPoint("BOTTOMRIGHT", selected, "BOTTOMRIGHT", -10, 9)

    local quickTitle = CreateText(quick, 8, { 0.48, 0.51, 0.58, 1 })
    quickTitle:SetPoint("TOPLEFT", selected, "BOTTOMLEFT", 2, -15)
    quickTitle:SetText(T("General Settings", "기본 설정"))

    local quickRows = {
        CreateDashboardQuickRow(quick, T("UI Scale", "UI 스케일"), "uiScale"),
        CreateDashboardQuickRow(quick, T("Display", "표시"), "display"),
        CreateDashboardQuickRow(quick, T("Profile Management", "프로필 관리"), "profiles.management"),
        CreateDashboardQuickRow(quick, T("Import / Export", "가져오기 / 내보내기"), "profiles.importExport"),
        CreateDashboardQuickRow(quick, T("Module Import", "모듈별 불러오기"), "profiles.moduleImport"),
    }
    local previousRow
    for _, row in ipairs(quickRows) do
        row:SetPoint("LEFT", quick, "LEFT", 10, 0)
        row:SetPoint("RIGHT", quick, "RIGHT", -10, 0)
        if previousRow then
            row:SetPoint("TOP", previousRow, "BOTTOM", 0, 0)
        else
            row:SetPoint("TOP", quickTitle, "BOTTOM", 0, -8)
        end
        row:SetScript("OnClick", function(self)
            parentFrame:NavigateToSection(self.target)
        end)
        previousRow = row
    end
    workspace.quickRows = quickRows

    local editButton = GUI.CreateStyledButton(quick, T("Open Edit Mode", "편집 모드 열기"), 100, 34)
    editButton:SetPoint("BOTTOMLEFT", quick, "BOTTOMLEFT", 10, 10)
    editButton:SetPoint("BOTTOMRIGHT", quick, "BOTTOMRIGHT", -10, 10)
    editButton:SetHeight(34)
    editButton:SetScript("OnClick", function()
        if DDingUI.Movers and DDingUI.Movers.ToggleConfigMode then
            DDingUI.Movers:ToggleConfigMode()
        end
    end)

    local stagePanel = CreateFrame("Frame", nil, body, "BackdropTemplate")
    stagePanel:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
    stagePanel:SetPoint("BOTTOMRIGHT", quick, "BOTTOMLEFT", -8, 0)
    SetSurface(stagePanel, THEME.panel, THEME.border)
    local stageHeader = CreateFrame("Frame", nil, stagePanel)
    stageHeader:SetPoint("TOPLEFT", stagePanel, "TOPLEFT", 0, 0)
    stageHeader:SetPoint("TOPRIGHT", stagePanel, "TOPRIGHT", 0, 0)
    stageHeader:SetHeight(40)
    stageHeader.title = CreateText(stageHeader, 11, { 0.96, 0.97, 0.99, 1 })
    stageHeader.title:SetPoint("LEFT", stageHeader, "LEFT", 12, 0)
    stageHeader.title:SetText(T("Current Layout", "현재 배치"))
    stageHeader.meta = CreateText(stageHeader, 8, { 0.48, 0.54, 0.62, 1 }, "RIGHT")
    stageHeader.meta:SetPoint("RIGHT", stageHeader, "RIGHT", -12, 0)
    CreateDivider(stageHeader, "BOTTOMLEFT", stageHeader, "BOTTOMLEFT", 0, 0)

    local stageFooter = CreateFrame("Frame", nil, stagePanel)
    stageFooter:SetPoint("BOTTOMLEFT", stagePanel, "BOTTOMLEFT", 0, 0)
    stageFooter:SetPoint("BOTTOMRIGHT", stagePanel, "BOTTOMRIGHT", 0, 0)
    stageFooter:SetHeight(30)
    CreateDivider(stageFooter, "TOPLEFT", stageFooter, "TOPLEFT", 0, 0)
    stageFooter.state = CreateText(stageFooter, 8, { 0.34, 0.9, 0.48, 1 }, "RIGHT")
    stageFooter.state:SetPoint("RIGHT", stageFooter, "RIGHT", -11, 0)
    stageFooter.state:SetText(T("Profile layout synced", "프로필 배치 동기화됨"))

    local stageHost = CreateFrame("Frame", nil, stagePanel)
    stageHost:SetPoint("TOPLEFT", stageHeader, "BOTTOMLEFT", 10, -10)
    stageHost:SetPoint("BOTTOMRIGHT", stageFooter, "TOPRIGHT", -10, 10)
    local stage = CreateFrame("Frame", nil, stageHost, "BackdropTemplate")
    SetSurface(stage, { 0.025, 0.03, 0.035, 1 }, { 0.24, 0.27, 0.3, 1 })
    if stage.SetClipsChildren then stage:SetClipsChildren(true) end
    workspace.stage = stage
    workspace.stageHost = stageHost
    workspace.stageHeader = stageHeader
    workspace.selectedCard = selected

    stage.screenLabel = CreateText(stage, 7, { 0.32, 0.37, 0.43, 1 })
    stage.screenLabel:SetPoint("TOPLEFT", stage, "TOPLEFT", 8, -7)
    stage.screenLabel:SetText(T("Screen Preview", "화면 미리보기"))
    stage.gridLines = {}
    for index = 1, 4 do
        local line = stage:CreateTexture(nil, "BACKGROUND")
        line:SetColorTexture(0.1, 0.12, 0.14, 0.72)
        stage.gridLines[index] = line
    end

    function workspace:ApplyNodeState(node, hovered)
        local selectedNode = self.selectedKey == node.descriptor.key
        if hovered or selectedNode then
            node:SetBackdropBorderColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
        else
            node:SetBackdropBorderColor(THEME.borderLight[1], THEME.borderLight[2], THEME.borderLight[3], 0.8)
        end
        node:SetAlpha(node.descriptor.enabled and 1 or 0.38)
    end

    function workspace:SelectDescriptor(descriptor)
        if not descriptor then return end
        self.selectedKey = descriptor.key
        self.selectedDescriptor = descriptor
        self.selectedCard.title:SetText(descriptor.label)
        self.selectedCard.path:SetText(descriptor.path)
        for _, node in ipairs(self.nodes) do self:ApplyNodeState(node, false) end
    end

    function workspace:AcquireIconSlot(node, index)
        local slot = node.icons[index]
        if slot then return slot end
        slot = CreateFrame("Frame", nil, node, "BackdropTemplate")
        SetSurface(slot, THEME.input, { 0.25, 0.28, 0.31, 1 })
        slot.texture = slot:CreateTexture(nil, "ARTWORK")
        slot.texture:SetPoint("TOPLEFT", slot, "TOPLEFT", 1, -1)
        slot.texture:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -1, 1)
        slot.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        node.icons[index] = slot
        return slot
    end

    function workspace:LayoutIconNode(node, viewRect, sourceRect)
        local descriptor = node.descriptor
        local config = descriptor.config or {}
        local count = #descriptor.textures
        local stageWidth, stageHeight = self.stage:GetWidth(), self.stage:GetHeight()
        local exactRects = {}
        local useExactRects = #descriptor.iconFrames == count and count > 0
        if useExactRects then
            for index = 1, count do
                exactRects[index] = DashboardFrameRect(descriptor.iconFrames[index])
                if not exactRects[index] then
                    useExactRects = false
                    break
                end
            end
        end
        if useExactRects then
            for index = 1, count do
                local rect = exactRects[index]
                local slot = self:AcquireIconSlot(node, index)
                slot:ClearAllPoints()
                slot:SetPoint("BOTTOMLEFT", node, "BOTTOMLEFT",
                    (rect.left - sourceRect.left) * stageWidth / viewRect.width,
                    (rect.bottom - sourceRect.bottom) * stageHeight / viewRect.height)
                slot:SetSize(math.max(1, rect.width * stageWidth / viewRect.width),
                    math.max(1, rect.height * stageHeight / viewRect.height))
                local texture = descriptor.textures[index] or 136243
                if slot._texture ~= texture then
                    slot.texture:SetTexture(texture)
                    slot._texture = texture
                end
                slot:Show()
            end
            for index = count + 1, #node.icons do node.icons[index]:Hide() end
            node.fill:Hide()
            node.text:Hide()
            return
        end

        local iconHeight = Clamp((tonumber(config.iconSize) or 36) * stageHeight / viewRect.height, 7, 28)
        local iconWidth = iconHeight * math.max(0.5, tonumber(config.aspectRatioCrop) or 1)
        local spacing = Clamp((tonumber(config.spacing) or 2) * stageWidth / viewRect.width, 0, 4)
        local limit = math.max(1, math.min(count, tonumber(config.rowLimit) or count))
        local horizontal = config.direction ~= "UP" and config.direction ~= "DOWN"
        local nodeWidth, nodeHeight = node:GetWidth(), node:GetHeight()
        for index = 1, count do
            local slot = self:AcquireIconSlot(node, index)
            local primary = (index - 1) % limit
            local secondary = math.floor((index - 1) / limit)
            local x, y
            if horizontal then
                x = config.direction == "LEFT"
                    and nodeWidth - iconWidth - primary * (iconWidth + spacing)
                    or primary * (iconWidth + spacing)
                y = config.growDirection == "UP"
                    and secondary * (iconHeight + spacing)
                    or nodeHeight - iconHeight - secondary * (iconHeight + spacing)
            else
                y = config.direction == "UP"
                    and primary * (iconHeight + spacing)
                    or nodeHeight - iconHeight - primary * (iconHeight + spacing)
                x = config.growDirection == "LEFT"
                    and nodeWidth - iconWidth - secondary * (iconWidth + spacing)
                    or secondary * (iconWidth + spacing)
            end
            slot:ClearAllPoints()
            slot:SetPoint("BOTTOMLEFT", node, "BOTTOMLEFT", x, y)
            slot:SetSize(iconWidth, iconHeight)
            local texture = descriptor.textures[index] or 136243
            if slot._texture ~= texture then
                slot.texture:SetTexture(texture)
                slot._texture = texture
            end
            slot:Show()
        end
        for index = count + 1, #node.icons do node.icons[index]:Hide() end
        node.fill:Hide()
        node.text:Hide()
    end

    function workspace:LayoutBarNode(node)
        for _, slot in ipairs(node.icons) do slot:Hide() end
        local width, height = node:GetWidth(), node:GetHeight()
        node.fill:ClearAllPoints()
        node.fill:SetPoint("TOPLEFT", node, "TOPLEFT", 1, -1)
        node.fill:SetPoint("BOTTOMLEFT", node, "BOTTOMLEFT", 1, 1)
        node.fill:SetWidth(math.max(1, (width - 2) * 0.72))
        local r, g, b, a = ColorValues(node.descriptor.color, { 0.22, 0.68, 0.84, 1 })
        node.fill:SetColorTexture(r, g, b, a)
        node.fill:Show()
        node.text:SetShown(width >= 58 and height >= 10)
    end

    function workspace:RefreshGeometry()
        local uiRect = DashboardFrameRect(UIParent)
        local stageWidth, stageHeight = self.stage:GetWidth(), self.stage:GetHeight()
        if not uiRect or not stageWidth or not stageHeight or stageWidth <= 1 or stageHeight <= 1 then return end
        local rects = {}
        for index, node in ipairs(self.nodes) do
            local descriptor = node.descriptor
            rects[index] = DashboardFrameRect(descriptor.frame)
                or DashboardConfiguredRect(descriptor.config, descriptor.width, descriptor.height, uiRect)
        end
        local viewRect = DashboardViewportRect(rects, uiRect)
        local meta = string.format("UIParent %.0f × %.0f  ·  %.2fx",
            uiRect.width, uiRect.height, viewRect.zoom)
        if self._stageMeta ~= meta then
            self.stageHeader.meta:SetText(meta)
            self._stageMeta = meta
        end
        local visible = 0
        for index, node in ipairs(self.nodes) do
            local descriptor = node.descriptor
            local rect = rects[index]
            if rect then
                local x = (rect.left - viewRect.left) * stageWidth / viewRect.width
                local y = (rect.bottom - viewRect.bottom) * stageHeight / viewRect.height
                local width = math.max(descriptor.kind == "bar" and 22 or 8, rect.width * stageWidth / viewRect.width)
                local height = math.max(descriptor.kind == "bar" and 5 or 8, rect.height * stageHeight / viewRect.height)
                node:ClearAllPoints()
                node:SetPoint("BOTTOMLEFT", self.stage, "BOTTOMLEFT", x, y)
                node:Show()
                if node._layoutWidth ~= width or node._layoutHeight ~= height
                    or node._layoutStageWidth ~= stageWidth or node._layoutStageHeight ~= stageHeight
                then
                    node:SetSize(width, height)
                    node._layoutWidth, node._layoutHeight = width, height
                    node._layoutStageWidth, node._layoutStageHeight = stageWidth, stageHeight
                    if descriptor.kind == "icons" then
                        self:LayoutIconNode(node, viewRect, rect)
                    else
                        self:LayoutBarNode(node)
                    end
                end
                visible = visible + 1
            else
                node:Hide()
            end
        end
        self.stage.empty:SetShown(visible == 0)
    end

    function workspace:CreateNode(descriptor)
        local node = CreateFrame("Button", nil, self.stage, "BackdropTemplate")
        node.descriptor = descriptor
        node.icons = {}
        SetSurface(node, { 0.05, 0.055, 0.065, 0.82 }, THEME.borderLight)
        node.fill = node:CreateTexture(nil, "ARTWORK")
        node.text = CreateText(node, 7, { 1, 1, 1, 1 }, "CENTER")
        node.text:SetPoint("CENTER")
        node.text:SetText(descriptor.label)
        node:SetScript("OnEnter", function(self)
            workspace:SelectDescriptor(self.descriptor)
            workspace:ApplyNodeState(self, true)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.descriptor.label, 1, 1, 1)
            GameTooltip:AddLine(self.descriptor.path, 0.58, 0.62, 0.68)
            GameTooltip:Show()
        end)
        node:SetScript("OnLeave", function(self)
            workspace:ApplyNodeState(self, false)
            GameTooltip:Hide()
        end)
        node:SetScript("OnClick", function(self)
            parentFrame:NavigateToSection(self.descriptor.target)
        end)
        self.nodes[#self.nodes + 1] = node
        self:ApplyNodeState(node, false)
        return node
    end

    function workspace:RebuildNodes()
        local selectedKey = self.selectedKey
        for _, node in ipairs(self.nodes) do
            node:Hide()
            node:SetParent(nil)
        end
        wipe(self.nodes)
        local descriptors = BuildDashboardDescriptors()
        local first = descriptors[1]
        local preferred
        for _, descriptor in ipairs(descriptors) do
            self:CreateNode(descriptor)
            if descriptor.key == selectedKey then
                preferred = descriptor
            elseif not preferred and descriptor.key == "group:Cooldowns" then
                preferred = descriptor
            end
        end
        self:SelectDescriptor(preferred or first)
        self._sourceSignature = DashboardSourceSignature()
        self:RefreshGeometry()
    end

    function workspace:RefreshQuickValues()
        local profile = DDingUI.db and DDingUI.db.profile or {}
        local general = profile.general or {}
        local scale = tonumber(general.uiScale) or (UIParent and UIParent:GetScale()) or 1
        self.quickRows[1].value:SetText(string.format("%.2f", scale))
        local hiddenRules = (general.hideWhileFlying and 1 or 0)
            + (general.hideWhileMounted and 1 or 0)
            + (general.hideInVehicle and 1 or 0)
        self.quickRows[2].value:SetText(hiddenRules > 0 and tostring(hiddenRules) or T("Always visible", "항상 표시"))
        self.quickRows[3].value:SetText(DDingUI.db and DDingUI.db.GetCurrentProfile
            and DDingUI.db:GetCurrentProfile() or "-")
        self.quickRows[4].value:SetText(T("Open", "열기"))
        self.quickRows[5].value:SetText(T("Open", "열기"))
    end

    function workspace:ResizeStage()
        local availableWidth = math.max(1, self.stageHost:GetWidth() - 10)
        local availableHeight = math.max(1, self.stageHost:GetHeight() - 10)
        local width = math.min(availableWidth, availableHeight * 16 / 9)
        local height = width * 9 / 16
        self.stage:ClearAllPoints()
        self.stage:SetPoint("CENTER", self.stageHost, "CENTER", 0, 0)
        self.stage:SetSize(width, height)
        local fractions = { 1 / 3, 2 / 3 }
        for index, fraction in ipairs(fractions) do
            local vertical = self.stage.gridLines[index]
            vertical:ClearAllPoints()
            vertical:SetPoint("TOPLEFT", self.stage, "TOPLEFT", width * fraction, 0)
            vertical:SetPoint("BOTTOMLEFT", self.stage, "BOTTOMLEFT", width * fraction, 0)
            vertical:SetWidth(1)
            local horizontal = self.stage.gridLines[index + 2]
            horizontal:ClearAllPoints()
            horizontal:SetPoint("TOPLEFT", self.stage, "TOPLEFT", 0, -height * fraction)
            horizontal:SetPoint("TOPRIGHT", self.stage, "TOPRIGHT", 0, -height * fraction)
            horizontal:SetHeight(1)
        end
        self:RefreshGeometry()
    end

    stage.empty = CreateText(stage, 10, { 0.48, 0.51, 0.58, 1 }, "CENTER")
    stage.empty:SetPoint("CENTER")
    stage.empty:SetText(T("No active layout elements", "표시할 배치 요소가 없습니다"))
    selected.open:SetScript("OnClick", function()
        if workspace.selectedDescriptor then
            parentFrame:NavigateToSection(workspace.selectedDescriptor.target)
        end
    end)

    function workspace:RefreshCurrent()
        self:RefreshQuickValues()
        local signature = DashboardSourceSignature()
        if signature ~= self._sourceSignature then
            self:RebuildNodes()
        else
            self:RefreshGeometry()
        end
    end

    function workspace:Release()
        self:SetScript("OnUpdate", nil)
        self.stageHost:SetScript("OnSizeChanged", nil)
        if self._resizeTimer then self._resizeTimer:Cancel(); self._resizeTimer = nil end
    end

    stageHost:SetScript("OnSizeChanged", function()
        if workspace._resizeTimer then workspace._resizeTimer:Cancel() end
        workspace._resizeTimer = C_Timer.NewTimer(0.04, function()
            workspace._resizeTimer = nil
            if workspace:IsShown() then workspace:ResizeStage() end
        end)
    end)
    workspace:SetScript("OnUpdate", function(self, elapsed)
        self._geometryElapsed = (self._geometryElapsed or 0) + elapsed
        self._sourceElapsed = (self._sourceElapsed or 0) + elapsed
        if self._geometryElapsed >= 0.25 then
            self._geometryElapsed = 0
            self:RefreshGeometry()
        end
        if self._sourceElapsed >= 0.8 then
            self._sourceElapsed = 0
            local signature = DashboardSourceSignature()
            if signature ~= self._sourceSignature then
                self:RebuildNodes()
                self:RefreshQuickValues()
            end
        end
    end)
    workspace:SetScript("OnHide", function(self) self:Release() end)
    workspace:RefreshQuickValues()
    C_Timer.After(0, function()
        if workspace:IsShown() then
            workspace:ResizeStage()
            workspace:RebuildNodes()
        end
    end)
end

function GUI.CreateSectionWorkspace(contentFrame, parentFrame, options, path)
    local requestedPath = parentFrame._requestedSubTabPath
    local requestedKind = options.workspaceKind or (path and path[1]) or "general"
    if requestedKind == "general" and not (requestedPath and #requestedPath > 0) then
        return CreateDashboardWorkspace(contentFrame, parentFrame)
    end

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
    SetSurface(workspace, THEME.shell, THEME.border)
    contentArea._sectionWorkspace = workspace
    workspace._parentFrame = parentFrame
    workspace._rootOptions = options
    workspace._rootPath = path or { kind }
    workspace.kind = kind

    local preview = CreateFrame("Frame", nil, workspace, "BackdropTemplate")
    preview:SetPoint("TOPLEFT", workspace, "TOPLEFT", 10, -10)
    preview:SetPoint("TOPRIGHT", workspace, "TOPRIGHT", -10, -10)
    preview:SetHeight(154)
    SetSurface(preview, THEME.panelRaised, THEME.border)
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
    SetSurface(navigation, THEME.sidebar, THEME.border)
    navigation.title = CreateText(navigation, 9, { 0.48, 0.51, 0.58, 1 })
    navigation.title:SetPoint("TOPLEFT", navigation, "TOPLEFT", 14, -13)
    navigation.title:SetText(T("Settings Sections", "설정 영역"))
    CreateDivider(navigation, "TOPLEFT", navigation, "TOPLEFT", 10, -37)
    navigation.rows = {}

    local settings = CreateFrame("Frame", nil, lower, "BackdropTemplate")
    settings:SetPoint("TOPLEFT", navigation, "TOPRIGHT", 8, 0)
    settings:SetPoint("BOTTOMRIGHT", lower, "BOTTOMRIGHT", 0, 0)
    SetSurface(settings, THEME.panel, THEME.border)
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
                row.background:SetColorTexture(THEME.bgMedium[1], THEME.bgMedium[2], THEME.bgMedium[3], 1)
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
        local viewportWidth = self.settingsScroll:GetWidth()
        if viewportWidth and viewportWidth > 80 then
            self.settingsChild:SetWidth(viewportWidth - 1)
        end
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

    function workspace:RefreshCurrent(preserveScroll)
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
