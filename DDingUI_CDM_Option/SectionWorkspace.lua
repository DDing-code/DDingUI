local _, ns = ...
local DDingUI = ns.Addon
local GUI = DDingUI.GUI
local Base = DDingUI.GUIBase
local L = Base.L
local FLAT = Base.FLAT
local THEME = Base.THEME
local SL = _G.DDingUI_StyleLib
-- [STYLE] StyleLib 1.3 rounded cards (helpers from GUIWidgets; absent in headless tests)
local RADIUS = Base.RADIUS or { card = 10, row = 8 }
local RoundFrame = Base.RoundFrame
local RoundTexture = Base.RoundTexture
local TintTexture = Base.TintTexture or function(tex, r, g, b, a) tex:SetColorTexture(r, g, b, a or 1) end
local ROUNDED = SL and SL.Rounded ~= false and RoundFrame ~= nil
local ROW_INSET = ROUNDED and 4 or 0
local PILL_ALPHA = 0.18
local HOVER_TINT = ROUNDED and { 1, 1, 1, 0.05 } or THEME.bgHover

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
    text:SetFont(FontPath(), math.max(12, tonumber(size) or 12), "") -- [STYLE] settings text >= 12pt
    text:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    text:SetJustifyH(justify or "LEFT")
    return text
end

--- [STYLE] Card surface: rounded when StyleLib 1.3 is available, square otherwise.
local function SetCard(frame, background, border)
    SetSurface(frame, background, border)
    if ROUNDED then RoundFrame(frame, RADIUS.card) end
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

-- [REFACTOR] Only the text-only general preview is signature driven; the bar sections copy the
-- live runtime frames on a timer, so every runtime setting change is picked up automatically.
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
    end
    return table.concat(parts, "|")
end

local NAV_ROW_NORMAL = ROUNDED and { 1, 1, 1, 0 } or { 0, 0, 0, 0 } -- [STYLE]

local function CreateNavigationRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:RegisterForClicks("LeftButtonUp")
    row.background = row:CreateTexture(nil, "BACKGROUND")
    row.background:SetAllPoints()
    if ROUNDED and RoundTexture then RoundTexture(row.background, RADIUS.row) end -- [STYLE]
    -- [STYLE] the per-row active bar is replaced by the navigation's sliding indicator
    row.index = CreateText(row, 12, { 0.38, 0.41, 0.47, 1 }, "RIGHT")
    row.index:SetWidth(22)
    row.label = CreateText(row, 12, { 0.78, 0.8, 0.85, 1 })
    row.label:SetWordWrap(false)
    -- [STYLE] background fade comes from SL.RowHover; these only swap the label colour
    row:SetScript("OnEnter", function(self)
        if self._isHeader or self._selected then return end
        self.label:SetTextColor(0.96, 0.97, 0.99, 1)
    end)
    row:SetScript("OnLeave", function(self)
        if self._workspace then self._workspace:RefreshNavigationState(true) end
    end)
    return row
end

local DASHBOARD_GROUP_LABEL_KEYS = {
    Cooldowns = "Essential Cooldowns",
    Buffs = "Buff Icons",
    Utility = "Utility Cooldowns",
}
local DashboardPreview = GUI.DashboardPreview
local DashboardFrameRect = DashboardPreview.Rect

local function DashboardFramesRect(frames)
    local left, right, bottom, top
    for _, frame in ipairs(frames) do
        local rect = DashboardFrameRect(frame)
        if rect then
            left = left and math.min(left, rect.left) or rect.left
            right = right and math.max(right, rect.left + rect.width) or rect.left + rect.width
            bottom = bottom and math.min(bottom, rect.bottom) or rect.bottom
            top = top and math.max(top, rect.bottom + rect.height) or rect.bottom + rect.height
        end
    end
    if left then return { left = left, bottom = bottom, width = right - left, height = top - bottom } end
end

local function DashboardViewportRect(rects, uiRect, stageWidth, stageHeight, zoom)
    local left, right, bottom, top
    for _, rect in pairs(rects) do
        left = left and math.min(left, rect.left) or rect.left
        right = right and math.max(right, rect.left + rect.width) or rect.left + rect.width
        bottom = bottom and math.min(bottom, rect.bottom) or rect.bottom
        top = top and math.max(top, rect.bottom + rect.height) or rect.bottom + rect.height
    end
    left, bottom = left or uiRect.left, bottom or uiRect.bottom
    right, top = right or uiRect.left + uiRect.width, top or uiRect.bottom + uiRect.height
    local scale = math.min(stageWidth * 0.88 / math.max(1, right - left),
        stageHeight * 0.88 / math.max(1, top - bottom), 2) * (zoom or 1)
    local width, height = stageWidth / scale, stageHeight / scale
    return {
        left = (left + right - width) * 0.5,
        bottom = (bottom + top - height) * 0.5,
        width = width, height = height, scale = scale,
    }
end

local function DashboardGroupLabel(groupName, settings)
    local localeKey = DASHBOARD_GROUP_LABEL_KEYS[groupName]
    return (localeKey and T(localeKey, nil)) or settings.name or groupName
end

local function BuildDashboardDescriptors(barsOnly)
    local profile = DDingUI.db and DDingUI.db.profile or {}
    local descriptors = {}
    local groups = {}
    -- [REFACTOR] barsOnly: the section previews sample only the resource/cast bars at 10 Hz
    for groupName, settings in pairs(not barsOnly and profile.groupSystem and profile.groupSystem.groups or {}) do
        if groupName ~= "Utility" and type(settings) == "table" and settings.enabled ~= false then
            groups[#groups + 1] = { name = groupName, settings = settings, order = tonumber(settings.order) or 999 }
        end
    end
    table.sort(groups, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.name < b.name
    end)
    local renderer = DDingUI.GroupRenderer
    for _, group in ipairs(groups) do
        local frame = renderer and renderer.groupFrames and renderer.groupFrames[group.name]
        local sources = {}
        local restricted = false
        -- [REFACTOR] slots the runtime layout keeps for an icon that is not visible (hidden or alpha 0).
        -- The copy draws real frames only, so such a slot is empty in game too; it is counted, not drawn.
        local emptySlots = 0
        if frame and frame._managedIcons and renderer.IsManagedIconInLayout then
            for index = 1, frame._iconCount or #frame._managedIcons do
                local icon = frame._managedIcons[index]
                local ok, inLayout = pcall(renderer.IsManagedIconInLayout, renderer, icon)
                if ok and not (issecretvalue and issecretvalue(inLayout)) then
                    if inLayout == true then
                        local visible = DashboardPreview.Read(icon, "IsVisible")
                        if visible == true then
                            sources[#sources + 1] = icon
                            local alpha = DashboardPreview.Read(icon, "GetEffectiveAlpha")
                            if type(alpha) == "number" and alpha < 0.01 then emptySlots = emptySlots + 1 end
                        elseif visible == false then
                            emptySlots = emptySlots + 1
                        end
                        restricted = restricted or visible == nil
                    end
                else
                    restricted = true
                end
            end
        end
        -- [REFACTOR] custom aura icons of the 12.1 aura container engine live in their own container
        -- next to the group's icons (not in _managedIcons); copy it too so they are not missing.
        local auraEngine = DDingUI.CustomIconAuraEngine
        local auraRecord = auraEngine and auraEngine.records and auraEngine.records[group.name]
        local auraContainer = auraRecord and auraRecord.active and auraRecord.container
        if auraContainer then
            local visible = DashboardPreview.Read(auraContainer, "IsVisible")
            if visible == true then sources[#sources + 1] = auraContainer end
            restricted = restricted or visible == nil
        end
        descriptors[#descriptors + 1] = {
            key = "group:" .. group.name,
            label = DashboardGroupLabel(group.name, group.settings),
            path = T("CDM Bars", "CDM 바") .. " / " .. DashboardGroupLabel(group.name, group.settings),
            target = "groupSystem.group_" .. group.name,
            frame = frame, sources = sources, restricted = restricted,
            groupName = group.name, emptySlots = emptySlots,
        }
    end

    local function AddFrame(key, label, target, frame, config, color, trackerIndex)
        if config.enabled == false then return end
        local visible = DashboardPreview.Read(frame, "IsVisible")
        descriptors[#descriptors + 1] = {
            key = key, label = label, path = label, target = target, frame = frame,
            sources = visible == true and { frame } or {},
            restricted = frame ~= nil and visible == nil,
            color = color, trackerIndex = trackerIndex,
            config = not trackerIndex and config or nil,
        }
    end
    local resources = DDingUI.ResourceBars
    -- [REFACTOR] A bar the runtime hides by rule (hideWhenMana on a DPS spec) never appears in game,
    -- so it is not forced on screen and not drawn; it is only listed as "hidden in game"
    -- (ResourceBars.IsManaHiddenForDPS). A resource the spec does not have is left out entirely.
    local ruleHidden = {}
    local function ShownByRule(key, label, getter, cfg)
        if not resources or not resources[getter] then return true end
        local resource = DashboardPreview.Read(resources, getter)
        if resource == nil then return false end
        if resources.IsManaHiddenForDPS and resources.IsManaHiddenForDPS(cfg, resource)
            and not (cfg and cfg.enabled == false) then
            ruleHidden[#ruleHidden + 1] = { key = key, label = label }
            return false
        end
        return true
    end
    local primaryLabel, secondaryLabel = T("Primary Resource", "주 자원"), T("Secondary Resource", "보조 자원")
    if ShownByRule("power", primaryLabel, "GetPrimaryResource", profile.powerBar) then
        AddFrame("power", primaryLabel, "resourceBars.primary",
            DDingUI.powerBar, profile.powerBar or {}, GetResourceColorSpec(false))
    end
    if ShownByRule("secondaryPower", secondaryLabel, "GetSecondaryResource", profile.secondaryPowerBar) then
        AddFrame("secondaryPower", secondaryLabel, "resourceBars.secondary",
            DDingUI.secondaryPowerBar, profile.secondaryPowerBar or {}, GetResourceColorSpec(true))
    end
    local cast = profile.castBar or {}
    AddFrame("cast", T("Player Cast Bar", "플레이어 시전 바"), "castBars.general",
        DDingUI.castBar, cast, cast.useClassColor and GetClassColorSpec() or cast.color)

    local tracked = DDingUI.GetTrackedBuffConfigs and DDingUI:GetTrackedBuffConfigs() or {}
    local bars = DDingUI.GetTrackedBuffBars and DDingUI:GetTrackedBuffBars() or {}
    local icons = DDingUI.GetTrackedBuffIcons and DDingUI:GetTrackedBuffIcons() or {}
    local texts = DDingUI.GetTrackedBuffTexts and DDingUI:GetTrackedBuffTexts() or {}
    local config = profile.buffTrackerBar or {}
    if config.enabled ~= false and not barsOnly then
        for index, entry in ipairs(tracked) do
            local parent = entry.parentGroup and tracked[entry.parentGroup]
            if not entry.isGroup and not entry.disabled and not (parent and parent.disabled) then
                local kind = entry.displayType or "bar"
                local source
                if kind == "bar" or kind == "ring" then source = bars[index]
                elseif kind == "icon" then source = icons[index]
                elseif kind == "text" then source = texts[index] end
                if source then
                    local color = entry.settings and entry.settings.barColor or config.barColor
                    if kind == "ring" then color = entry.settings and entry.settings.ringColor or { 1, 0.8, 0, 1 } end
                    AddFrame("aura:" .. (entry.uid or index), entry.name or T("Buff Tracker", "커스텀 오라"),
                        "buffTracker", source, entry.settings or {}, color, index)
                end
            end
        end
    end
    return descriptors, ruleHidden
end

-- ============================================================
-- [REFACTOR] Live layout: nothing is estimated any more. While a dashboard or section preview is
-- open (out of combat) DashboardPreview.LiveSession puts the real CDM elements on screen through
-- the runtime's own preview paths (custom aura preview mode, test cast, forced inactive buffs /
-- custom icons like edit mode), and every node is a DashboardPreview.Paint copy of a shown frame.
-- Elements that are still not shown are listed, never drawn as a guessed shape.
-- ============================================================
local SECTION_PREVIEW_KEYS = {
    resourceBars = { power = "primary", secondaryPower = "secondary" },
    castBars = { cast = "general" },
}

local function BuildSectionDescriptors(kind)
    local descriptors, hidden = {}, {}
    if kind == "buffBar" then
        local viewer = _G.BuffBarCooldownViewer
        local config = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.buffBarViewer or {}
        if config.enabled ~= false and viewer then
            local visible = DashboardPreview.Read(viewer, "IsVisible")
            descriptors[1] = {
                key = "buffBar", label = T("Tracked Bars", "추적중인 막대"), frame = viewer,
                sources = visible == true and { viewer } or {}, restricted = visible == nil,
            }
        end
        return descriptors, hidden
    end
    local wanted = SECTION_PREVIEW_KEYS[kind]
    if not wanted then return descriptors, hidden end
    local all, ruleHidden = BuildDashboardDescriptors(true)
    for _, descriptor in ipairs(all) do
        if wanted[descriptor.key] then
            descriptor.entryKey = wanted[descriptor.key]
            descriptors[#descriptors + 1] = descriptor
        end
    end
    for _, entry in ipairs(ruleHidden or {}) do
        if wanted[entry.key] then hidden[#hidden + 1] = entry.label end
    end
    return descriptors, hidden
end

--- One line for the elements that are configured but not drawn right now.
local function DescribeNotShown(labels, restricted, ruleHidden, emptySlots)
    local parts = {}
    if (emptySlots or 0) > 0 then
        parts[#parts + 1] = string.format(T("Empty slots in game %d", "게임 화면에서도 빈 칸 %d"), emptySlots)
    end
    if #labels > 0 then parts[#parts + 1] = T("Not on screen", "화면에 없음") .. ": " .. table.concat(labels, ", ") end
    if #ruleHidden > 0 then parts[#parts + 1] = T("Hidden in game", "게임에서 숨김") .. ": " .. table.concat(ruleHidden, ", ") end
    if restricted > 0 then parts[#parts + 1] = string.format(T("Display limited %d", "표시 제한 %d"), restricted) end
    return table.concat(parts, "  ·  ")
end

local function CreateLayoutPreview(parent, kind)
    local visual = CreateFrame("Frame", nil, parent)
    visual:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -54)
    visual:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -12, 10)
    visual.kind = kind
    visual.nodes = {}
    visual.live = true
    -- The copy surface stands for the game screen, so it stays square like the real frames.
    local stage = CreateFrame("Frame", nil, visual, "BackdropTemplate")
    stage:SetAllPoints(visual)
    SetSurface(stage, THEME.input, THEME.border)
    if stage.SetClipsChildren then stage:SetClipsChildren(true) end
    visual.stage = stage
    visual.hint = CreateText(stage, 12, THEME.textDim, "CENTER")
    visual.hint:SetPoint("LEFT", stage, "LEFT", 12, 0)
    visual.hint:SetPoint("RIGHT", stage, "RIGHT", -12, 0)
    visual.hint:SetWordWrap(true)
    visual.note = CreateText(stage, 12, THEME.textDim, "LEFT")
    visual.note:SetPoint("BOTTOMLEFT", stage, "BOTTOMLEFT", 8, 4)
    visual.note:SetPoint("BOTTOMRIGHT", stage, "BOTTOMRIGHT", -8, 4)
    visual.note:SetWordWrap(false)
    DashboardPreview.LiveSession:Begin(visual)

    local function AcquireNode(index)
        local node = visual.nodes[index]
        if node then return node end
        node = CreateFrame("Frame", nil, stage, "BackdropTemplate")
        node.visual = CreateFrame("Frame", nil, node)
        node.visual:SetAllPoints(node)
        node.highlight = CreateFrame("Frame", nil, node, "BackdropTemplate")
        node.highlight:SetPoint("TOPLEFT", node, "TOPLEFT", -3, 3)
        node.highlight:SetPoint("BOTTOMRIGHT", node, "BOTTOMRIGHT", 3, -3)
        node.highlight:SetFrameLevel(node:GetFrameLevel() + 24)
        SetSurface(node.highlight, { 0, 0, 0, 0 }, THEME.accent)
        node.highlight:Hide()
        visual.nodes[index] = node
        return node
    end

    -- [REFACTOR] per-frame light follow (bar values, time text, spark) of the painted copies
    function visual:SyncLive()
        for _, node in ipairs(self.nodes) do
            if node:IsShown() then DashboardPreview.SyncLive(node.visual) end
        end
    end

    function visual:Release()
        DashboardPreview.LiveSession:End(self)
        for _, node in ipairs(self.nodes) do
            DashboardPreview.Clear(node.visual)
            node:Hide()
        end
    end

    function visual:Refresh(selectedKey)
        local descriptors, ruleHidden = BuildSectionDescriptors(self.kind)
        local rects, nodes, notShown = {}, {}, {}
        self.partialCount = 0
        for index, descriptor in ipairs(descriptors) do
            local node = AcquireNode(index)
            node.descriptor = descriptor
            nodes[index] = node
            rects[index] = DashboardFramesRect(descriptor.sources)
            if descriptor.restricted then self.partialCount = self.partialCount + 1 end
            if not rects[index] and not descriptor.restricted then notShown[#notShown + 1] = descriptor.label end
        end
        for index = #descriptors + 1, #self.nodes do
            DashboardPreview.Clear(self.nodes[index].visual)
            self.nodes[index]:Hide()
        end

        local left, right, bottom, top
        for index = 1, #descriptors do
            local rect = rects[index]
            if rect then
                left = left and math.min(left, rect.left) or rect.left
                right = right and math.max(right, rect.left + rect.width) or rect.left + rect.width
                bottom = bottom and math.min(bottom, rect.bottom) or rect.bottom
                top = top and math.max(top, rect.bottom + rect.height) or rect.bottom + rect.height
            end
        end
        self.note:SetText(DescribeNotShown(left and notShown or {}, 0, ruleHidden))
        local stageW, stageH = self.stage:GetWidth() or 0, self.stage:GetHeight() or 0
        self.sizeRatio = nil
        if not left or stageW <= 1 or stageH <= 1 then
            for _, node in ipairs(nodes) do
                DashboardPreview.Clear(node.visual)
                node:Hide()
            end
            local message
            if DashboardPreview.LiveSession.combatBlocked then
                message = T("Combat display limit", "전투 중 표시 제한: 전투가 끝나면 실제 표시를 다시 복사합니다")
            elseif #ruleHidden > 0 and #descriptors == 0 then
                message = T("Hidden in game", "게임에서 숨김") .. ": " .. table.concat(ruleHidden, ", ")
            else
                message = T("Nothing on screen", "화면에 표시된 요소가 없습니다")
            end
            self.hint:SetText(message)
            self.hint:Show()
            return
        end
        self.hint:Hide()

        -- Real on-screen size (UIParent units → this frame's units), shrunk only when it does not fit.
        local uiScale = DashboardPreview.Read(UIParent, "GetEffectiveScale") or 1
        local ownScale = DashboardPreview.Read(self.stage, "GetEffectiveScale") or 1
        local trueScale = ownScale > 0 and uiScale / ownScale or 1
        local width, height = math.max(1, right - left), math.max(1, top - bottom)
        local fit = math.min(1, (stageW - 16) / (width * trueScale), (stageH - 16) / (height * trueScale))
        local scale = trueScale * math.max(0.05, fit)
        local viewLeft = left - (stageW / scale - width) / 2
        local viewBottom = bottom - (stageH / scale - height) / 2
        self.sizeRatio = fit

        for index, node in ipairs(nodes) do
            local rect = rects[index]
            if rect then
                node:ClearAllPoints()
                node:SetPoint("BOTTOMLEFT", self.stage, "BOTTOMLEFT",
                    (rect.left - viewLeft) * scale, (rect.bottom - viewBottom) * scale)
                node:SetSize(rect.width * scale, rect.height * scale)
                node:Show()
                local _, partial = DashboardPreview.Paint(node.visual, node.descriptor.sources,
                    rect, scale, node.descriptor.color)
                if partial then self.partialCount = self.partialCount + 1 end
                local selected = selectedKey and node.descriptor.entryKey
                    and (selectedKey == node.descriptor.entryKey
                        or selectedKey:sub(1, #node.descriptor.entryKey + 1) == node.descriptor.entryKey .. "."
                        or selectedKey:match(node.descriptor.entryKey .. "$"))
                node.highlight:SetShown(selected and true or false)
            else
                DashboardPreview.Clear(node.visual)
                node:Hide()
            end
        end
    end

    return visual
end

local function CreateResourcePreview(parent) return CreateLayoutPreview(parent, "resourceBars") end
local function CreateCastPreview(parent) return CreateLayoutPreview(parent, "castBars") end
local function CreateTrackedPreview(parent) return CreateLayoutPreview(parent, "buffBar") end

local PREVIEW_BUILDERS = {
    general = CreateGeneralPreview,
    resourceBars = CreateResourcePreview,
    castBars = CreateCastPreview,
    buffBar = CreateTrackedPreview,
}

local function CreateDashboardQuickRow(parent, label, target)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(43)
    row.target = target
    row.background = row:CreateTexture(nil, "BACKGROUND")
    row.background:SetAllPoints()
    if ROUNDED and RoundTexture then RoundTexture(row.background, RADIUS.row) end -- [STYLE]
    TintTexture(row.background, 0, 0, 0, 0)
    row.label = CreateText(row, 11, THEME.text)
    row.label:SetPoint("LEFT", row, "LEFT", 9, 0)
    row.label:SetText(label)
    row.value = CreateText(row, 10, THEME.textDim, "RIGHT")
    row.value:SetWordWrap(false)
    row.value:SetPoint("RIGHT", row, "RIGHT", -9, 0)
    row.value:SetPoint("LEFT", row.label, "RIGHT", 8, 0)
    local divider = row:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    divider:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    divider:SetHeight(1)
    divider:SetColorTexture(THEME.border[1], THEME.border[2], THEME.border[3], 0.72)
    row:SetScript("OnEnter", function(self)
        TintTexture(self.background, HOVER_TINT[1], HOVER_TINT[2], HOVER_TINT[3], HOVER_TINT[4] or 1) -- [STYLE]
        self.label:SetTextColor(1, 1, 1, 1)
    end)
    row:SetScript("OnLeave", function(self)
        TintTexture(self.background, 0, 0, 0, 0)
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
    SetCard(workspace, THEME.shell, THEME.border) -- [STYLE] fills the rounded content card
    contentArea._sectionWorkspace = workspace
    workspace._parentFrame = parentFrame
    workspace.nodes = {}
    workspace.nodeByKey = {}
    workspace.freeNodes = {}
    workspace.zoom = 1

    local header = CreateFrame("Frame", nil, workspace)
    workspace.header = header
    header:SetPoint("TOPLEFT", workspace, "TOPLEFT", 10, -10)
    header:SetPoint("TOPRIGHT", workspace, "TOPRIGHT", -10, -10)
    header:SetHeight(52)
    header.title = CreateText(header, 15, { 0.96, 0.97, 0.99, 1 })
    header.title:SetPoint("TOPLEFT", header, "TOPLEFT", 4, -4)
    header.title:SetText(T("Dashboard", "대시보드"))
    header.subtitle = CreateText(header, 11, THEME.textDim)
    header.subtitle:SetPoint("TOPLEFT", header.title, "BOTTOMLEFT", 0, -5)
    header.subtitle:SetText(T("Current profile layout and status", "현재 프로필의 배치와 상태"))
    header.live = CreateText(header, 9, { 0.34, 0.9, 0.48, 1 }, "RIGHT")
    header.live:SetPoint("RIGHT", header, "RIGHT", -4, 4)
    header.live:SetText(T("Live Layout", "실시간 배치"))
    if ROUNDED and SL.CreateStatusRing then -- [STYLE] StyleLib 1.3 status ring instead of a square dot
        header.liveDot = SL.CreateStatusRing(header, 11, { 0.34, 0.9, 0.48, 1 })
    else
        header.liveDot = header:CreateTexture(nil, "ARTWORK")
        header.liveDot:SetSize(6, 6)
        header.liveDot:SetColorTexture(0.34, 0.9, 0.48, 1)
    end
    header.liveDot:SetPoint("RIGHT", header.live, "LEFT", -7, 0)
    CreateDivider(header, "BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)

    local body = CreateFrame("Frame", nil, workspace)
    body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
    body:SetPoint("BOTTOMRIGHT", workspace, "BOTTOMRIGHT", -10, 10)

    local quick = CreateFrame("Frame", nil, body, "BackdropTemplate")
    quick:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, 0)
    quick:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
    quick:SetWidth(210)
    quick.header = CreateText(quick, 12, { 0.96, 0.97, 0.99, 1 })
    quick.header:SetPoint("TOPLEFT", quick, "TOPLEFT", 12, -13)
    quick.header:SetText(T("Quick Settings", "빠른 설정"))
    CreateDivider(quick, "TOPLEFT", quick, "TOPLEFT", 10, -40)

    local selected = CreateFrame("Frame", nil, quick, "BackdropTemplate")
    selected:SetPoint("TOPLEFT", quick, "TOPLEFT", 10, -51)
    selected:SetPoint("TOPRIGHT", quick, "TOPRIGHT", -10, -51)
    selected:SetHeight(126)
    selected.eyebrow = CreateText(selected, 10, THEME.accent)
    selected.eyebrow:SetPoint("TOPLEFT", selected, "TOPLEFT", 10, -9)
    selected.eyebrow:SetText(T("Selected Element", "선택한 요소"))
    selected.title = CreateText(selected, 13, { 0.96, 0.97, 0.99, 1 })
    selected.title:SetPoint("TOPLEFT", selected.eyebrow, "BOTTOMLEFT", 0, -6)
    selected.title:SetPoint("RIGHT", selected, "RIGHT", -10, 0)
    selected.title:SetHeight(32)
    selected.path = CreateText(selected, 10, THEME.textDim)
    selected.path:SetPoint("TOPLEFT", selected.title, "BOTTOMLEFT", 0, -5)
    selected.path:SetPoint("RIGHT", selected, "RIGHT", -10, 0)
    selected.path:SetWordWrap(false)
    selected.open = GUI.CreateStyledButton(selected, T("Open Settings", "설정 열기"), 100, 26)
    selected.open:SetPoint("BOTTOMLEFT", selected, "BOTTOMLEFT", 10, 9)
    selected.open:SetPoint("BOTTOMRIGHT", selected, "BOTTOMRIGHT", -10, 9)

    local quickTitle = CreateText(quick, 10, THEME.textDim)
    quickTitle:SetPoint("TOPLEFT", selected, "BOTTOMLEFT", 2, -15)
    quickTitle:SetText(T("Dashboard basic settings", "기본 설정"))

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
    local stageHeader = CreateFrame("Frame", nil, stagePanel)
    stageHeader:SetPoint("TOPLEFT", stagePanel, "TOPLEFT", 0, 0)
    stageHeader:SetPoint("TOPRIGHT", stagePanel, "TOPRIGHT", 0, 0)
    stageHeader:SetHeight(40)
    stageHeader.title = CreateText(stageHeader, 11, { 0.96, 0.97, 0.99, 1 })
    stageHeader.title:SetPoint("LEFT", stageHeader, "LEFT", 12, 0)
    stageHeader.title:SetText(T("Current Layout", "현재 배치"))
    stageHeader.meta = CreateText(stageHeader, 11, THEME.textDim, "RIGHT")
    stageHeader.meta:SetPoint("RIGHT", stageHeader, "RIGHT", -174, 0)
    CreateDivider(stageHeader, "BOTTOMLEFT", stageHeader, "BOTTOMLEFT", 0, 0)

    local stageFooter = CreateFrame("Frame", nil, stagePanel)
    stageFooter:SetPoint("BOTTOMLEFT", stagePanel, "BOTTOMLEFT", 0, 0)
    stageFooter:SetPoint("BOTTOMRIGHT", stagePanel, "BOTTOMRIGHT", 0, 0)
    stageFooter:SetHeight(30)
    CreateDivider(stageFooter, "TOPLEFT", stageFooter, "TOPLEFT", 0, 0)
    stageFooter.state = CreateText(stageFooter, 10, THEME.textDim, "RIGHT")
    stageFooter.state:SetPoint("RIGHT", stageFooter, "RIGHT", -11, 0)
    workspace.stageFooter = stageFooter

    local stageHost = CreateFrame("Frame", nil, stagePanel)
    stageHost:SetPoint("TOPLEFT", stageHeader, "BOTTOMLEFT", 10, -10)
    stageHost:SetPoint("BOTTOMRIGHT", stageFooter, "TOPRIGHT", -10, 10)
    local stage = CreateFrame("Frame", nil, stageHost, "BackdropTemplate")
    SetSurface(stage, THEME.input, THEME.border)
    if stage.SetClipsChildren then stage:SetClipsChildren(true) end
    workspace.stage = stage
    workspace.stageHost = stageHost
    workspace.stageHeader = stageHeader
    workspace.selectedCard = selected

    local zoomControls = {
        { label = "+", name = T("Zoom In", "확대"), factor = 1.2, width = 28 },
        { label = "-", name = T("Zoom Out", "축소"), factor = 1 / 1.2, width = 28 },
        { label = T("Fit Layout", "배치 맞춤"), width = 72 },
    }
    local buttonOffset = -10
    for _, control in ipairs(zoomControls) do
        local button = GUI.CreateStyledButton(stageHeader, control.label, control.width, 28)
        button:SetPoint("RIGHT", stageHeader, "RIGHT", buttonOffset, 0)
        buttonOffset = buttonOffset - control.width - 6
        button:SetScript("OnClick", function()
            workspace.zoom = control.factor and Clamp(workspace.zoom * control.factor, 0.5, 3) or 1
            if not control.factor then workspace.panX, workspace.panY = 0, 0 end
            workspace:RefreshGeometry()
        end)
        button:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(control.name or control.label)
            GameTooltip:Show()
        end)
        button:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
    stage:EnableMouse(true)
    stage:EnableMouseWheel(true)
    stage:SetScript("OnMouseWheel", function(_, delta)
        workspace.zoom = Clamp(workspace.zoom * 1.15 ^ delta, 0.5, 3)
        workspace:RefreshGeometry()
    end)
    stage:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            local x, y = GetCursorPosition()
            workspace._drag = { x = x, y = y, panX = workspace.panX or 0, panY = workspace.panY or 0 }
        end
    end)
    stage:SetScript("OnMouseUp", function() workspace._drag = nil end)

    stage.screenLabel = CreateText(stage, 10, THEME.textDim)
    stage.screenLabel:SetPoint("TOPLEFT", stage, "TOPLEFT", 8, -7)
    stage.screenLabel:SetText(T("Screen Preview", "화면 미리보기"))
    stage.gridLines = {}
    for index = 1, 4 do
        local line = stage:CreateTexture(nil, "BACKGROUND")
        line:SetColorTexture(0.1, 0.12, 0.14, 0.72)
        stage.gridLines[index] = line
    end

    stage.guideLayer = CreateFrame("Frame", nil, stage)
    stage.guideLayer:SetAllPoints(stage)
    stage.guideLayer:SetFrameLevel(stage:GetFrameLevel() + 20)
    stage.selectionGuides = {}
    for index = 1, 2 do
        local line = stage.guideLayer:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.55)
        line:Hide()
        stage.selectionGuides[index] = line
    end
    stage.selectionCenter = stage.guideLayer:CreateTexture(nil, "OVERLAY")
    stage.selectionCenter:SetSize(5, 5)
    stage.selectionCenter:SetColorTexture(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
    stage.selectionCenter:Hide()
    stage.selectionReadout = CreateText(stage.guideLayer, 7, { 0.72, 0.76, 0.82, 1 }, "RIGHT")
    stage.selectionReadout:SetPoint("BOTTOMRIGHT", stage.guideLayer, "BOTTOMRIGHT", -7, 6)
    stage.selectionReadout:Hide()

    function workspace:RefreshSelectionGuides()
        local node = self.selectedNode
        local vertical, horizontal = self.stage.selectionGuides[1], self.stage.selectionGuides[2]
        if not node or not node:IsShown() or not node._sourceRect or not node._stageX then
            vertical:Hide()
            horizontal:Hide()
            self.stage.selectionCenter:Hide()
            self.stage.selectionReadout:Hide()
            return
        end

        local centerX = node._stageX + node._layoutWidth * 0.5
        local centerY = node._stageY + node._layoutHeight * 0.5
        vertical:ClearAllPoints()
        vertical:SetPoint("TOP", self.stage, "TOPLEFT", centerX, 0)
        vertical:SetPoint("BOTTOM", self.stage, "BOTTOMLEFT", centerX, 0)
        vertical:SetWidth(1)
        vertical:Show()
        horizontal:ClearAllPoints()
        horizontal:SetPoint("LEFT", self.stage, "BOTTOMLEFT", 0, centerY)
        horizontal:SetPoint("RIGHT", self.stage, "BOTTOMRIGHT", 0, centerY)
        horizontal:SetHeight(1)
        horizontal:Show()
        self.stage.selectionCenter:ClearAllPoints()
        self.stage.selectionCenter:SetPoint("CENTER", self.stage, "BOTTOMLEFT", centerX, centerY)
        self.stage.selectionCenter:Show()

        local rect = node._sourceRect
        self.stage.selectionReadout:SetFormattedText(
            "X %.0f  Y %.0f   %.0f × %.0f",
            rect.left, rect.bottom, rect.width, rect.height
        )
        self.stage.selectionReadout:Show()
    end

    function workspace:ApplyNodeState(node, hovered)
        local selectedNode = self.selectedKey == node.descriptor.key
        local highlight = node.highlight or node
        if hovered or node._hovered or selectedNode then
            highlight:SetBackdropBorderColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
        else
            highlight:SetBackdropBorderColor(THEME.borderLight[1], THEME.borderLight[2], THEME.borderLight[3], node._active and 0 or 0.35)
        end
    end

    function workspace:SelectDescriptor(descriptor)
        if not descriptor then return end
        self.selectedKey = descriptor.key
        self.selectedDescriptor = descriptor
        self.selectedCard.title:SetText(descriptor.label)
        self.selectedCard.path:SetText(descriptor.path)
        self.selectedNode = nil
        for _, node in ipairs(self.nodes) do
            if node.descriptor.key == descriptor.key then self.selectedNode = node end
            self:ApplyNodeState(node, false)
        end
        self:RefreshSelectionGuides()
    end

    function workspace:RefreshGeometry()
        local uiRect = DashboardFrameRect(UIParent)
        local stageWidth, stageHeight = self.stage:GetWidth(), self.stage:GetHeight()
        if not uiRect or stageWidth <= 1 or stageHeight <= 1 then return end
        -- [REFACTOR] Only frames that are really on screen are drawn (DashboardPreview.Paint copies).
        -- The live session has already put inactive elements on screen; whatever is still not shown
        -- is listed in the footer instead of being drawn as a guessed shape.
        local rects = {}
        for index, node in ipairs(self.nodes) do
            rects[index] = DashboardFramesRect(node.descriptor.sources)
        end
        local viewRect = DashboardViewportRect(rects, uiRect, stageWidth, stageHeight, self.zoom)
        viewRect.left = viewRect.left + (self.panX or 0)
        viewRect.bottom = viewRect.bottom + (self.panY or 0)
        self.viewRect = viewRect
        self.stageHeader.meta:SetFormattedText("%.0f%%", viewRect.scale * 100)
        local visible, partial, notShown = 0, 0, {}
        for index, node in ipairs(self.nodes) do
            local rect = rects[index]
            node._active = rect ~= nil
            node._partial = node.descriptor.restricted
            if rect then
                local x = (rect.left - viewRect.left) * viewRect.scale
                local y = (rect.bottom - viewRect.bottom) * viewRect.scale
                local width, height = rect.width * viewRect.scale, rect.height * viewRect.scale
                node:ClearAllPoints()
                node:SetPoint("BOTTOMLEFT", self.stage, "BOTTOMLEFT", x, y)
                node:SetSize(width, height)
                node._stageX, node._stageY = x, y
                node._sourceRect = rect
                node._layoutWidth, node._layoutHeight = width, height
                local count, limited = DashboardPreview.Paint(node.visual, node.descriptor.sources,
                    rect, viewRect.scale, node.descriptor.color)
                node._partial = node._partial or limited
                node.text:SetText(node.descriptor.label)
                node.text:SetShown(count == 0 and width > 100 and height > 16)
                node:Show()
                if node._partial then partial = partial + 1 end
                visible = visible + 1
                self:ApplyNodeState(node, false)
            else
                node._stageX, node._stageY, node._sourceRect = nil, nil, nil
                DashboardPreview.Clear(node.visual)
                node:Hide()
                if node._partial then partial = partial + 1
                else notShown[#notShown + 1] = node.descriptor.label end
            end
        end
        self.stage.empty:SetShown(visible == 0)
        local status = string.format(T("Dashboard shown count", "%d개 표시"), visible)
        local emptySlots = 0
        for _, node in ipairs(self.nodes) do emptySlots = emptySlots + (node.descriptor.emptySlots or 0) end
        local extra = DescribeNotShown(notShown, partial, self._ruleHidden or {}, emptySlots)
        if extra ~= "" then status = status .. "  ·  " .. extra end
        self.stageFooter.state:SetText(status)
        self.stageFooter.state:SetTextColor(unpack(partial > 0 and THEME.warning or THEME.textDim))
        self:RefreshLiveBadge()
        self:RefreshSelectionGuides()
    end

    -- [REFACTOR] Tell the user the preview is borrowing the game screen (or why it can't right now).
    function workspace:RefreshLiveBadge()
        local session = DashboardPreview.LiveSession
        local live = self.header.live
        if session.combatBlocked then
            live:SetText(T("Combat display limit short", "전투 중 표시 제한 · 보이는 것만 복사"))
            live:SetTextColor(THEME.warning[1], THEME.warning[2], THEME.warning[3], 1)
        elseif session:IsActive() then
            live:SetText(T("Shown on game screen for preview", "미리보기용으로 게임 화면에 표시 중"))
            live:SetTextColor(0.34, 0.9, 0.48, 1)
        else
            live:SetText(T("Live Layout", "실시간 배치"))
            live:SetTextColor(0.34, 0.9, 0.48, 1)
        end
    end

    function workspace:CreateNode(descriptor)
        local node = table.remove(self.freeNodes)
        if node then node.descriptor = descriptor; return node end
        node = CreateFrame("Button", nil, self.stage, "BackdropTemplate")
        node.descriptor = descriptor
        node:SetHitRectInsets(-4, -4, -4, -4)
        node.visual = CreateFrame("Frame", nil, node)
        node.visual:SetAllPoints(node)
        node.visual:EnableMouse(false)
        node.highlight = CreateFrame("Frame", nil, node, "BackdropTemplate")
        node.highlight:SetAllPoints(node)
        node.highlight:SetFrameLevel(node:GetFrameLevel() + 24)
        node.highlight:EnableMouse(false)
        SetSurface(node.highlight, { 0, 0, 0, 0 }, THEME.borderLight)
        node.text = CreateText(node, 11, THEME.textDim, "CENTER")
        node.text:SetAllPoints(node)
        node:SetScript("OnEnter", function(self)
            self._hovered = true
            workspace:ApplyNodeState(self, true)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.descriptor.label, 1, 1, 1)
            GameTooltip:AddLine(self.descriptor.path, 0.58, 0.62, 0.68)
            local rect = self._sourceRect
            if rect then
                GameTooltip:AddDoubleLine(
                    T("Position", "위치"),
                    string.format("X %.0f  Y %.0f", rect.left, rect.bottom),
                    0.62, 0.66, 0.72, 0.94, 0.95, 0.97
                )
                GameTooltip:AddDoubleLine(
                    T("Size", "크기"),
                    string.format("%.0f × %.0f", rect.width, rect.height),
                    0.62, 0.66, 0.72, 0.94, 0.95, 0.97
                )
            end
            GameTooltip:Show()
        end)
        node:SetScript("OnLeave", function(self)
            self._hovered = nil
            workspace:ApplyNodeState(self, false)
            GameTooltip:Hide()
        end)
        node:SetScript("OnClick", function(self)
            workspace:SelectDescriptor(self.descriptor)
            workspace:OpenDescriptor(self.descriptor)
        end)
        self:ApplyNodeState(node, false)
        return node
    end

    function workspace:RebuildNodes()
        local selectedKey = self.selectedKey
        local descriptors, ruleHidden = BuildDashboardDescriptors()
        local labels = {}
        for _, entry in ipairs(ruleHidden or {}) do labels[#labels + 1] = entry.label end
        self._ruleHidden = labels
        local retained = {}
        for _, descriptor in ipairs(descriptors) do retained[descriptor.key] = true end
        for key, node in pairs(self.nodeByKey) do
            if not retained[key] then
                node:Hide()
                node._hovered = nil
                DashboardPreview.Clear(node.visual)
                self.freeNodes[#self.freeNodes + 1] = node
                self.nodeByKey[key] = nil
            end
        end
        wipe(self.nodes)
        local first = descriptors[1]
        local preferred
        for _, descriptor in ipairs(descriptors) do
            local node = self.nodeByKey[descriptor.key] or self:CreateNode(descriptor)
            node.descriptor = descriptor
            self.nodeByKey[descriptor.key] = node
            self.nodes[#self.nodes + 1] = node
            if descriptor.key == selectedKey then
                preferred = descriptor
            elseif not preferred and descriptor.key == "group:Cooldowns" then
                preferred = descriptor
            end
        end
        if preferred or first then self:SelectDescriptor(preferred or first)
        else
            self.selectedDescriptor, self.selectedNode, self.selectedKey = nil, nil, nil
            self.selectedCard.title:SetText("-")
            self.selectedCard.path:SetText("")
        end
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
        local width = math.max(1, self.stageHost:GetWidth())
        local height = math.max(1, self.stageHost:GetHeight())
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
    function workspace:OpenDescriptor(descriptor)
        if not descriptor then return end
        parentFrame:NavigateToSection(descriptor.target)
        local trackerPanel = parentFrame.contentArea._btPanel
        if descriptor.trackerIndex and trackerPanel and trackerPanel.SelectTracker then
            trackerPanel:SelectTracker(descriptor.trackerIndex)
        end
    end
    selected.open:SetScript("OnClick", function() workspace:OpenDescriptor(workspace.selectedDescriptor) end)

    function workspace:RefreshCurrent()
        self:RefreshQuickValues()
        self:RebuildNodes()
    end

    function workspace:Release()
        DashboardPreview.LiveSession:End(self) -- [REFACTOR] restore what the live layout turned on
        self:SetScript("OnUpdate", nil)
        self._drag = nil
        for _, node in ipairs(self.nodes) do
            DashboardPreview.Clear(node.visual)
        end
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
        if self._drag and not IsMouseButtonDown("LeftButton") then self._drag = nil end
        if self._drag and self.viewRect then
            local x, y = GetCursorPosition()
            local scale = self.stage:GetEffectiveScale() * self.viewRect.scale
            self.panX = self._drag.panX - (x - self._drag.x) / scale
            self.panY = self._drag.panY - (y - self._drag.y) / scale
            self:RefreshGeometry()
        end
        self._geometryElapsed = (self._geometryElapsed or 0) + elapsed
        if self._geometryElapsed >= 0.25 then
            self._geometryElapsed = 0
            self:RefreshCurrent()
        else
            -- [REFACTOR] between full copies only bar values / texts / sparks follow, every frame
            -- (OnUpdate only runs while the dashboard is shown and is removed on hide)
            for _, node in ipairs(self.nodes) do
                if node:IsShown() then DashboardPreview.SyncLive(node.visual) end
            end
        end
    end)
    workspace:SetScript("OnHide", function(self) self:Release() end)
    -- [REFACTOR] put every CDM element on screen while the dashboard is open (out of combat only)
    DashboardPreview.LiveSession:Begin(workspace)
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
    SetCard(workspace, THEME.shell, THEME.border) -- [STYLE] fills the rounded content card
    contentArea._sectionWorkspace = workspace
    workspace._parentFrame = parentFrame
    workspace._rootOptions = options
    workspace._rootPath = path or { kind }
    workspace.kind = kind

    local preview = CreateFrame("Frame", nil, workspace, "BackdropTemplate")
    preview:SetPoint("TOPLEFT", workspace, "TOPLEFT", 10, -10)
    preview:SetPoint("TOPRIGHT", workspace, "TOPRIGHT", -10, -10)
    preview:SetHeight(154)
    SetCard(preview, THEME.panelRaised, THEME.border) -- [STYLE]
    preview.title = CreateText(preview, 14, { 0.96, 0.97, 0.99, 1 })
    preview.title:SetPoint("TOPLEFT", preview, "TOPLEFT", 14, -11)
    preview.title:SetText(T(meta.title, meta.fallback))
    preview.subtitle = CreateText(preview, 10, { 0.48, 0.51, 0.58, 1 })
    preview.subtitle:SetPoint("TOPLEFT", preview.title, "BOTTOMLEFT", 0, -5)
    preview.subtitle:SetText(T(meta.subtitle, meta.subtitleFallback))
    preview.badge = CreateText(preview, 12, { 0.34, 0.9, 0.48, 1 }, "RIGHT")
    preview.badge:SetPoint("TOPRIGHT", preview, "TOPRIGHT", -14, -15)
    preview.badge:SetText(T("Live Preview", "실시간 미리보기"))
    -- [STYLE] no full-width divider: the square screen copy below separates itself from the header
    -- [REFACTOR] no "Test Cast" button: the live layout session keeps the runtime test cast running

    local lower = CreateFrame("Frame", nil, workspace)
    lower:SetPoint("TOPLEFT", preview, "BOTTOMLEFT", 0, -8)
    lower:SetPoint("BOTTOMRIGHT", workspace, "BOTTOMRIGHT", -10, 10)

    local navigation = CreateFrame("Frame", nil, lower, "BackdropTemplate")
    navigation:SetPoint("TOPLEFT", lower, "TOPLEFT", 0, 0)
    navigation:SetPoint("BOTTOMLEFT", lower, "BOTTOMLEFT", 0, 0)
    navigation:SetWidth(190)
    SetCard(navigation, THEME.sidebar, THEME.border) -- [STYLE]
    navigation.title = CreateText(navigation, 9, { 0.48, 0.51, 0.58, 1 })
    navigation.title:SetPoint("TOPLEFT", navigation, "TOPLEFT", 14, -13)
    navigation.title:SetText(T("Settings Sections", "설정 영역"))
    CreateDivider(navigation, "TOPLEFT", navigation, "TOPLEFT", 10, -37)
    navigation.rows = {}
    -- [STYLE] one sliding selection marker (StyleLib 1.2); 1.3: rounded pill under the rows
    if SL and SL.CreateIndicator then
        if ROUNDED then
            navigation.indicator = SL.CreateIndicator(navigation, 190 - ROW_INSET * 2, 39,
                { THEME.accent[1], THEME.accent[2], THEME.accent[3], PILL_ALPHA },
                { radius = RADIUS.row, layer = "BACKGROUND", subLevel = 1, x = ROW_INSET })
        else
            local indicatorLayer = CreateFrame("Frame", nil, navigation)
            indicatorLayer:SetAllPoints(navigation)
            indicatorLayer:SetFrameLevel(navigation:GetFrameLevel() + 20)
            navigation.indicator = SL.CreateIndicator(indicatorLayer, 3, 39, THEME.accent)
        end
    end

    local settings = CreateFrame("Frame", nil, lower, "BackdropTemplate")
    settings:SetPoint("TOPLEFT", navigation, "TOPRIGHT", 8, 0)
    settings:SetPoint("BOTTOMRIGHT", lower, "BOTTOMRIGHT", 0, 0)
    SetCard(settings, THEME.panel, THEME.border) -- [STYLE]
    if ROUNDED and SL.AddWatermark then -- [STYLE] faint series logo, bottom-right of the detail card
        settings.watermark = SL.AddWatermark(settings, "CDM", { height = 144 })
    end
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

    function workspace:RefreshNavigationState(keepBackground, animateIndicator)
        local selectableIndex = 0
        local selectedRow
        for _, row in ipairs(self.navigation.rows) do
            local entry = row._entry
            if entry and not entry.isHeader then selectableIndex = selectableIndex + 1 end
            row._selected = entry and not entry.isHeader and entry.key == self.selectedKey
            if row._selected and row:IsShown() then selectedRow = row end
            if not entry or entry.isHeader then
                TintTexture(row.background, 0, 0, 0, 0)
                row.index:SetText("")
                row.label:SetTextColor(0.48, 0.51, 0.58, 1)
            elseif row._selected then
                if ROUNDED then -- [STYLE] the pill marks the selection
                    TintTexture(row.background, 0, 0, 0, 0)
                else
                    row.background:SetColorTexture(THEME.bgMedium[1], THEME.bgMedium[2], THEME.bgMedium[3], 1)
                end
                row.index:SetText(string.format("%02d", selectableIndex))
                row.index:SetTextColor(1, 0.38, 0.08, 1)
                row.label:SetTextColor(1, 1, 1, 1)
            else
                -- [STYLE] on mouse-leave RowHover fades the background out itself
                if not keepBackground then TintTexture(row.background, 0, 0, 0, 0) end
                row.index:SetText(string.format("%02d", selectableIndex))
                row.index:SetTextColor(0.38, 0.41, 0.47, 1)
                row.label:SetTextColor(0.78, 0.8, 0.85, 1)
            end
        end
        local indicator = self.navigation.indicator
        if indicator and not keepBackground then -- mouse-leave must not cut a running slide
            if selectedRow then
                indicator:MoveTo(selectedRow, animateIndicator == true)
            else
                indicator:HideIndicator()
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
            row:SetPoint("TOPLEFT", self.navigation, "TOPLEFT", ROW_INSET, -y) -- [STYLE]
            row:SetPoint("RIGHT", self.navigation, "RIGHT", -ROW_INSET, 0)
            local height = entry.isHeader and 27 or 39
            row:SetHeight(height)
            row.label:ClearAllPoints()
            -- [STYLE] single LEFT anchor + width so RowHover can nudge the label 2px
            local navWidth = self.navigation:GetWidth()
            if not navWidth or navWidth <= 0 then navWidth = 190 end
            navWidth = navWidth - ROW_INSET * 2 -- [STYLE]
            if entry.isHeader then
                row.index:Hide()
                row.label:SetPoint("LEFT", row, "LEFT", 14, -2)
                row.label:SetWidth(math.max(20, navWidth - 14 - 10))
                row.label:SetFont(FontPath(), 12, "") -- [STYLE]
            else
                local indexLeft = 10 + (entry.depth or 0) * 8
                row.index:Show()
                row.index:ClearAllPoints()
                row.index:SetPoint("LEFT", row, "LEFT", indexLeft, 0)
                row.label:SetPoint("LEFT", row.index, "RIGHT", 9, 0)
                row.label:SetWidth(math.max(20, navWidth - indexLeft - 22 - 9 - 10))
                row.label:SetFont(FontPath(), 12, "") -- [STYLE]
            end
            row.label:SetText(entry.label)
            if SL and SL.RowHover then
                SL.RowHover(row, {
                    bg = row.background,
                    label = not entry.isHeader and row.label or nil,
                    normal = NAV_ROW_NORMAL,
                    hover = HOVER_TINT,
                    isActive = function(r) return r._isHeader or r._selected end,
                })
            end
            local capturedKey = entry.key
            row:SetScript("OnClick", entry.isHeader and nil or function()
                self:SelectEntry(capturedKey, false, true) -- [STYLE] user click: slide + stagger
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
        local visual = self.previewVisual
        if visual and visual.Refresh then
            visual:Refresh(self.selectedKey)
        end
        if visual and visual.live then
            -- [REFACTOR] say whether the copy is at in-game size and whether anything is limited
            local ratio = visual.sizeRatio
            local text
            if not ratio then
                text = T("Live Preview", "실시간 미리보기")
            elseif ratio >= 0.995 then
                text = T("Actual size", "실제 크기")
            else
                text = string.format(T("Scaled to %d%%", "%d%%로 축소"), math.floor(ratio * 100 + 0.5))
            end
            if DashboardPreview.LiveSession.combatBlocked then
                text = text .. "  ·  " .. T("Combat display limit short", "전투 중 표시 제한 · 보이는 것만 복사")
            elseif DashboardPreview.LiveSession:IsActive() then
                text = text .. "  ·  " .. T("Shown on game screen for preview", "미리보기용으로 게임 화면에 표시 중")
            end
            if (visual.partialCount or 0) > 0 then
                text = text .. "  ·  " .. T("Display limited", "표시 제한")
            end
            self.preview.badge:SetText(text)
            local warn = (visual.partialCount or 0) > 0
            self.preview.badge:SetTextColor(warn and THEME.warning[1] or 0.34, warn and THEME.warning[2] or 0.9,
                warn and THEME.warning[3] or 0.48, 1)
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

    function workspace:SelectEntry(key, preserveScroll, fromUser)
        local entry = FindEntry(self.entries, key)
        if not entry then return end
        self.selectedKey = entry.key
        DDingUI._sectionWorkspaceSelections = DDingUI._sectionWorkspaceSelections or {}
        DDingUI._sectionWorkspaceSelections[self.kind] = entry.key
        self:RefreshNavigationState(false, fromUser)
        self:RefreshPreview()
        self:RenderSettings(preserveScroll)
        -- [STYLE] sub-page change: settings rows fade in top-down (clicks only)
        if fromUser and SL and SL.StaggerIn then
            local regions = {}
            for _, widget in ipairs(self.settingsChild.widgets or {}) do
                if #regions >= 12 then break end
                if widget and widget.IsShown and widget:IsShown() then regions[#regions + 1] = widget end
            end
            if #regions > 0 then SL.StaggerIn(regions, { step = 0.03, offset = 4 }) end
        end
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
        if self.previewVisual and self.previewVisual.Release then self.previewVisual:Release() end
    end

    workspace:SetScript("OnUpdate", function(self, elapsed)
        self._previewElapsed = (self._previewElapsed or 0) + elapsed
        local live = self.previewVisual and self.previewVisual.live
        -- [REFACTOR] live copies: full copy 4x a second (layout/look), bar values / texts / sparks
        -- follow every frame in between so the cast bar runs smoothly
        if self._previewElapsed < (live and 0.25 or 0.12) then
            if live and self.previewVisual.SyncLive then self.previewVisual:SyncLive() end
            return
        end
        self._previewElapsed = 0
        if live then self:RefreshPreview(); return end
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
