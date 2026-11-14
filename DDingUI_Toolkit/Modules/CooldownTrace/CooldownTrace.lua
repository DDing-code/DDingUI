local _, ns = ...
local SL = _G.DDingUI_StyleLib
local C, L = SL.Colors, ns.L
local BORDER_COLOR = {C.bg.input[1], C.bg.input[2], C.bg.input[3], 1}
local Data = ns.CooldownTraceData
local Sensor = ns.CooldownTraceSensor
local Trace = {}
Trace.__index = Trace
ns.CooldownTraceEngine = Trace
local TOKENS = {"player", "party1", "party2", "party3", "party4"}
local BASE_ICON = 36 -- OmniCD extra bars scale this base size.
local BAR_POINTS = {TOPLEFT=true, TOPRIGHT=true, BOTTOMLEFT=true, BOTTOMRIGHT=true}

-- [REFACTOR] kind "common" = frame 0, "barN" = extra bar N, a category = that category alone.
function Trace.New(moduleName, kind, titleKey)
    local index = type(kind) == "string" and tonumber(kind:match("^bar(%d)$"))
    return setmetatable({moduleName=moduleName, kind=kind, titleKey=titleKey, barIndex=index}, Trace)
end
local ICONS = 0
for class, spells in pairs(Data.cooldowns) do
    ICONS = math.max(ICONS, #spells + #Data.defensives[class] + #Data.cc[class])
end

local function Secret(value)
    return issecretvalue and issecretvalue(value) or false
end

local function PublicNumber(value)
    return not Secret(value) and type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

local function Restricted()
    if InCombatLockdown() then return true end
    if C_Secrets and C_Secrets.ShouldAurasBeSecret then
        local ok, restricted = pcall(C_Secrets.ShouldAurasBeSecret)
        return not ok or Secret(restricted) or restricted == true
    end
    return false
end

local function Number(value, default, low, high)
    return PublicNumber(value) and math.max(low, math.min(high, value)) or default
end

-- [12.0.1] Match units, never party slot numbers (party frames may be sorted).
local function MatchesUnit(frame, unit)
    if Secret(frame) or not frame or not frame.IsVisible or not frame:IsVisible() then return false end
    local token
    if frame.GetAttribute then token = frame:GetAttribute("unit") end
    if Secret(token) then return false end
    if token == nil then token = frame.unit end
    if Secret(token) or type(token) ~= "string" then return false end
    local same = UnitIsUnit(token, unit)
    return not Secret(same) and same == true
end

local function PartyAnchor(unit)
    -- shortcut: Custom frames need a loaded LibGetFrame; embed it if standalone support is required.
    local lib = LibStub("LibGetFrame-1.0", true)
    if lib and lib.GetUnitFrame then
        local ok, frame = pcall(lib.GetUnitFrame, unit, {ignorePlayerFrame=false})
        if ok and MatchesUnit(frame, unit) then return frame end
    end
    for _, frame in ipairs(CompactPartyFrame and CompactPartyFrame.memberUnitFrames or {}) do
        if MatchesUnit(frame, unit) then return frame end
    end
    for i = 1, 4 do
        local frame = PartyFrame and PartyFrame["MemberFrame" .. i]
        if MatchesUnit(frame, unit) then return frame end
    end
    for index = 1, 40 do
        local grouped = _G["CompactRaidGroup" .. math.ceil(index / 5) .. "Member" .. ((index - 1) % 5 + 1)]
        local frame = _G["CompactRaidFrame" .. index]
        if MatchesUnit(grouped, unit) then return grouped end
        if MatchesUnit(frame, unit) then return frame end
    end
    if MatchesUnit(PlayerFrame, unit) then return PlayerFrame end
end

local ATTACH_POINTS = {
    RIGHT = {"LEFT", "RIGHT"}, LEFT = {"RIGHT", "LEFT"},
    TOP = {"BOTTOM", "TOP"}, BOTTOM = {"TOP", "BOTTOM"},
}

local function Text(parent, size, color)
    local text = parent:CreateFontString(nil, "OVERLAY")
    text:SetFont(SL.Font.path, size, "OUTLINE")
    text:SetTextColor(unpack(color))
    text:SetJustifyH("LEFT")
    return text
end

-- [12.0.1] Native translations orbit without scripts, reparenting or reading protected geometry.
local function Orbit(glow, particles, index, size, phase, period, particleSize)
    local particle = particles[index]
    if not particle then
        particle = glow:CreateTexture(nil, "OVERLAY")
        particle:SetBlendMode("ADD")
        particle.animation = particle:CreateAnimationGroup()
        particle.animation:SetLooping("REPEAT")
        particle.legs = {}
        for order = 1, 5 do
            local leg = particle.animation:CreateAnimation("Translation")
            leg:SetOrder(order)
            particle.legs[order] = leg
        end
        particles[index] = particle
    end
    particle.animation:Stop()
    local side = math.max(1, size)
    local distance = (phase % 1) * side * 4
    local edge, along = math.floor(distance / side), distance % side
    local corners = {{0, 0}, {0, side}, {side, side}, {side, 0}}
    local directions = {{0, 1}, {1, 0}, {0, -1}, {-1, 0}}
    local corner, direction = corners[edge+1], directions[edge+1]
    particle:ClearAllPoints()
    particle:SetPoint("CENTER", glow, "BOTTOMLEFT", corner[1]+direction[1]*along, corner[2]+direction[2]*along)
    particle:SetSize(particleSize, particleSize)
    for order, leg in ipairs(particle.legs) do
        local length = order == 1 and side-along or order == 5 and along or side
        direction = directions[(edge+order-1)%4+1]
        leg:SetOffset(direction[1]*length, direction[2]*length)
        leg:SetDuration(period*length/(side*4))
    end
    return particle
end

-- [STYLE] Configure only addon-owned visuals; aura visibility stays engine-owned.
-- `muted` is the per-spell OmniCD glow switch (Spells tab).
local function ConfigureGlow(glow, db, used, muted, size)
    local fallback = used and C.status.warning or C.status.success
    local color = db[used and "useGlowColor" or "glowColor"]
    if Secret(color) or type(color) ~= "table" then color = fallback end
    local r, g, b, a = Number(color[1], fallback[1], 0, 1), Number(color[2], fallback[2], 0, 1),
        Number(color[3], fallback[3], 0, 1), Number(color[4], 1, 0, 1)
    local thickness = Number(db.glowThickness, 2, 1, 6)
    local enabled = not muted and (used and db.useGlow == true or not used and db.activeGlow ~= false)
    local effectType = db[used and "useGlowType" or "glowType"]
    if effectType ~= "autocast" and effectType ~= "button" and effectType ~= "normal" then effectType = "pixel" end
    glow.effectType = effectType
    if glow.edges then
        glow.nativeSize = size or glow.nativeSize
        for _, particles in ipairs({glow.pixels, glow.sparks}) do
            for _, particle in ipairs(particles) do particle.animation:Stop(); particle:Hide() end
        end
        -- [12.0.1] CDM's native-region approach keeps every style inside the protected button.
        for index, edge in ipairs(glow.edges) do
            edge:SetColorTexture(r, g, b, effectType == "normal" and a*.45 or a)
            edge:SetShown(effectType == "normal")
            local width = effectType == "normal" and thickness*2 or thickness
            if index <= 2 then edge:SetHeight(width) else edge:SetWidth(width) end
        end
        if effectType == "pixel" then
            local length = math.max(thickness, math.floor(glow.nativeSize*.3))
            local count = math.ceil(length/thickness)
            for dash = 0, 7 do
                for dot = 0, count-1 do
                    local phase = dash/8 + dot*length/count/(glow.nativeSize*4)
                    local pixel = Orbit(glow, glow.pixels, dash*count+dot+1, glow.nativeSize, phase, 4, thickness)
                    pixel:SetColorTexture(r, g, b, a)
                    pixel:Show()
                    if enabled then pixel.animation:Play() end
                end
            end
        elseif effectType == "autocast" then
            for index = 1, 16 do
                local ring = math.floor((index-1)/4)+1
                local spark = Orbit(glow, glow.sparks, index, glow.nativeSize, (index-1)%4/4, 8*ring, 8-ring)
                spark:SetTexture("Interface\\Artifacts\\Artifacts")
                spark:SetTexCoord(.8115234375, .9169921875, .8798828125, .9853515625)
                spark:SetDesaturated(true)
                spark:SetVertexColor(r, g, b, a)
                spark:Show()
                if enabled then spark.animation:Play() end
            end
        end
        if effectType == "button" and not glow.ants then
            local ants = glow:CreateTexture(nil, "OVERLAY")
            ants:SetPoint("TOPLEFT", -5, 5)
            ants:SetPoint("BOTTOMRIGHT", 5, -5)
            ants:SetAtlas("RotationHelper_Ants_Flipbook_2x", false)
            ants:SetBlendMode("ADD")
            ants:SetDesaturated(true)
            ants.animation = ants:CreateAnimationGroup()
            ants.animation:SetLooping("REPEAT")
            ants.flipbook = ants.animation:CreateAnimation("FlipBook")
            ants.flipbook:SetFlipBookRows(6)
            ants.flipbook:SetFlipBookColumns(5)
            ants.flipbook:SetFlipBookFrames(30)
            glow.ants = ants
        end
        if glow.ants then
            glow.ants:SetVertexColor(r, g, b, a)
            glow.ants:SetShown(effectType == "button")
            glow.ants.animation:Stop()
            glow.ants.flipbook:SetDuration(Number(db.glowSpeed, .4, .1, 1.5))
            if enabled and effectType == "button" then glow.ants.animation:Play() end
        end
    else
        SL.HideAllGlows(glow)
        if enabled then
            local color = {r, g, b, a}
            if effectType == "autocast" then SL.ShowAutocastGlow(glow, color)
            elseif effectType == "button" then SL.ShowButtonGlow(glow, color)
            elseif effectType == "normal" then SL.ShowNormalGlow(glow, color, thickness)
            else SL.ShowPixelGlow(glow, color, 8, .25, nil, thickness) end
        end
    end
    glow.animation:Stop()
    glow:SetAlpha(1)
    glow.pulseAlpha:SetDuration(Number(db.glowSpeed, .4, .1, 1.5))
    if enabled and db.glowPulse ~= false then glow.animation:Play() end
    glow:SetShown(enabled)
end

local function ActiveGlow(frame, db, used, protectedSize)
    local glow = CreateFrame("Frame", nil, frame)
    glow:SetAllPoints(frame)
    glow:SetFrameLevel(frame:GetFrameLevel() + 8)
    glow:EnableMouse(false)
    -- [12.0.1] Only AuraButtons need native regions: LibCustomGlow reparents pooled frames and runs Lua OnUpdate.
    if protectedSize then
        glow.nativeSize = protectedSize
        glow.pixels, glow.sparks = {}, {}
        glow.edges = {}
        for index, points in ipairs({
            {"TOPLEFT", "TOPRIGHT"}, {"BOTTOMLEFT", "BOTTOMRIGHT"},
            {"TOPLEFT", "BOTTOMLEFT"}, {"TOPRIGHT", "BOTTOMRIGHT"},
        }) do
            local edge = glow:CreateTexture(nil, "OVERLAY")
            glow.edges[index] = edge
            edge:SetColorTexture(unpack(C.status.success))
            edge:SetBlendMode("ADD")
            edge:SetPoint(points[1])
            edge:SetPoint(points[2])
            if index <= 2 then edge:SetHeight(2) else edge:SetWidth(2) end
        end
    end
    local animation = glow:CreateAnimationGroup()
    animation:SetLooping("BOUNCE")
    local alpha = animation:CreateAnimation("Alpha")
    alpha:SetOrder(1)
    alpha:SetFromAlpha(.3)
    alpha:SetToAlpha(1)
    alpha:SetDuration(.4)
    glow.animation, glow.pulseAlpha = animation, alpha
    ConfigureGlow(glow, db, used)
    return glow
end

local function ConfigureCooldown(cooldown, db)
    cooldown:SetDrawSwipe(db.showSwipe ~= false)
    cooldown:SetHideCountdownNumbers(db.showNumbers == false)
end

-- [STYLE] Cropped art, countdown and charge count; border follows the shared icon settings.
local function Icon(parent, size)
    local icon = CreateFrame("Frame", nil, parent)
    icon:SetSize(size, size)
    icon:EnableMouse(false)
    icon.border = icon:CreateTexture(nil, "BACKGROUND")
    icon.border:SetPoint("TOPLEFT", -1, 1)
    icon.border:SetPoint("BOTTOMRIGHT", 1, -1)
    local r, g, b = unpack(C.bg.input)
    icon.border:SetColorTexture(r, g, b, 1)
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints()
    icon.texture:SetTexCoord(.07, .93, .07, .93)
    icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.cooldown:SetAllPoints()
    icon.cooldown:SetDrawEdge(false)
    icon.cooldown:SetDrawSwipe(true)
    icon.cooldown:SetHideCountdownNumbers(false)
    local overlay = CreateFrame("Frame", nil, icon)
    overlay:SetAllPoints()
    -- [12.0.1] Above the hidden-timer grey cover (cooldown + 1), below its number window.
    overlay:SetFrameLevel(icon.cooldown:GetFrameLevel() + 3)
    icon.overlay = overlay
    -- Public countdown numbers sit on their own layer so a newer hidden use can fade them.
    icon.timerLayer = CreateFrame("Frame", nil, overlay)
    icon.timerLayer:SetAllPoints()
    icon.text = Text(icon.timerLayer, 12, C.text.highlight)
    icon.text:SetPoint("CENTER")
    icon.count = Text(overlay, 11, C.text.highlight)
    icon.count:SetPoint("BOTTOMRIGHT", -2, 2)
    icon.count:SetJustifyH("RIGHT")
    icon:Hide()
    return icon
end

local function Clock(seconds)
    seconds = math.ceil(seconds)
    if seconds < 60 then return tostring(seconds) end
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- [STYLE] KiraUI-style color assumes ready until a cooldown is observed; keep unknown opacity separate.
local function SetIconState(icon, known, cooling, db)
    icon.unknown = not known
    icon.texture:SetDesaturated(cooling)
    icon:SetAlpha(known and 1 or Number(db.unknownAlpha, 1, .1, 1))
end

local function SpellTexture(id)
    local texture = C_Spell.GetSpellTexture(id)
    if Secret(texture) or texture == nil then return 134400 end
    return texture
end

local function ClassColor(class)
    if type(class) ~= "string" then return nil end
    return (C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class))
        or (RAID_CLASS_COLORS or {})[class]
end

-- OmniCD "Truncate Name": keep the first N UTF-8 characters; 0 keeps the whole name.
local function Truncate(name, count)
    if type(name) ~= "string" or type(count) ~= "number" or count <= 0 then return name end
    local result, n = "", 0
    for char in name:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        n = n + 1
        if n > count then return result end
        result = result .. char
    end
    return result
end

local function ColorOf(value, fallback)
    if Secret(value) or type(value) ~= "table" then value = fallback end
    return Number(value[1], fallback[1], 0, 1), Number(value[2], fallback[2], 0, 1),
        Number(value[3], fallback[3], 0, 1), Number(value[4], fallback[4] or 1, 0, 1)
end

local function ConfigureBorder(icon, db)
    local width = Number(db.borderThickness, 1, 1, 6)
    icon.border:ClearAllPoints()
    icon.border:SetPoint("TOPLEFT", icon.texture, "TOPLEFT", -width, width)
    icon.border:SetPoint("BOTTOMRIGHT", icon.texture, "BOTTOMRIGHT", width, -width)
    icon.border:SetColorTexture(ColorOf(db.borderColor, BORDER_COLOR))
    icon.border:SetShown(db.showBorder ~= false)
end

local function NameFont(text, db, size)
    local font = not Secret(db.nameFont) and type(db.nameFont) == "string" and db.nameFont or SL.Font.path
    if not text:SetFont(font, size, "OUTLINE") then text:SetFont(SL.Font.path, size, "OUTLINE") end
end

-- [STYLE] Reuse the tracked icon and its cooldown; only its presentation changes.
local function ConfigureIcon(icon, trace)
    local size, bars = trace.size, trace.bars
    -- [STYLE] OmniCD status bar timer: icon | status bar, name inside, timer at the right end.
    local omni = trace.barIndex ~= nil and bars
    local invert = omni and trace.nameBar and trace.db.invertNameBar == true
    icon:SetSize(trace.itemWidth, size)
    icon.texture:ClearAllPoints()
    icon.texture:SetPoint(invert and "TOPRIGHT" or "TOPLEFT")
    icon.texture:SetSize(size, size)
    ConfigureBorder(icon, trace.fx)
    icon.cooldown:ClearAllPoints()
    if omni then icon.cooldown:SetAllPoints(icon.texture) else icon.cooldown:SetPoint("TOPRIGHT") end
    icon.cooldown:SetSize(size, size)
    icon.text:ClearAllPoints()
    if omni and not trace.nameBar then icon.text:SetPoint("RIGHT", icon, "RIGHT", -3, 0)
    elseif omni then icon.text:SetPoint("CENTER", icon.texture, "CENTER", 0, 0)
    else icon.text:SetPoint(bars and "RIGHT" or "CENTER", bars and -5 or 0, 0) end
    if not icon.owner then
        icon.owner = Text(icon.overlay, 10, C.text.dim)
        icon.owner:SetWordWrap(false)
    end
    icon.owner:ClearAllPoints()
    icon.owner:SetPoint("TOPLEFT", icon.texture, "BOTTOMLEFT", Number(trace.db.nameOfsX, 0, -100, 100),
        -2 + Number(trace.db.nameOfsY, 0, -100, 100))
    icon.owner:SetWidth(size)
    NameFont(icon.owner, trace.db, Number(trace.db.nameFontSize, 10, 6, 32))
    icon.owner:SetJustifyH(trace.barIndex and "CENTER" or "LEFT")
    icon.owner:SetShown(not bars and trace.combined and trace.showNames ~= false)
    if bars and not icon.bar then
        icon.bar = CreateFrame("StatusBar", nil, icon)
        icon.bar:SetStatusBarTexture(SL.Textures.flat)
        icon.bar:SetStatusBarColor(unpack(C.status.success))
        icon.barBG = icon.bar:CreateTexture(nil, "BACKGROUND")
        icon.barBG:SetAllPoints()
        icon.barBG:SetColorTexture(unpack(C.bg.input))
        icon.label = Text(icon.overlay, 12, C.text.highlight)
        icon.label:SetWordWrap(false)
    end
    if omni and not icon.barBorder then
        icon.barBorder = icon:CreateTexture(nil, "BACKGROUND")
        icon.barBorder:SetColorTexture(0, 0, 0, 1)
        icon.spark = icon.bar:CreateTexture(nil, "OVERLAY")
        icon.spark:SetColorTexture(1, 1, 1, .8)
        icon.spark:SetWidth(2)
        icon.spark:SetBlendMode("ADD")
        -- Native countdown numbers for the player's own spells, drawn at the bar end without a swipe.
        icon.barCooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
        icon.barCooldown:SetDrawSwipe(false)
        icon.barCooldown:SetDrawEdge(false)
        icon.barCooldown:SetFrameLevel(icon.cooldown:GetFrameLevel() + 2)
    end
    if icon.bar then
        local db = trace.db
        icon.bar:ClearAllPoints()
        if omni then
            local width = trace.statusWidth or (trace.itemWidth - size)
            if invert then icon.bar:SetPoint("TOPRIGHT", icon, "TOPRIGHT", -size, 0)
            else icon.bar:SetPoint("TOPLEFT", icon, "TOPLEFT", size, 0) end
            icon.bar:SetSize(width, size)
            if icon.bar.SetIgnoreParentAlpha then icon.bar:SetIgnoreParentAlpha(db.useIconAlpha ~= true) end
            icon.bar:GetStatusBarTexture():SetShown(not trace.nameBar)
            icon.barBorder:ClearAllPoints()
            icon.barBorder:SetPoint("TOPLEFT", icon.bar, "TOPLEFT", -1, 1)
            icon.barBorder:SetPoint("BOTTOMRIGHT", icon.bar, "BOTTOMRIGHT", 1, -1)
            icon.barBorder:SetShown(db.hideBorder ~= true and not trace.nameBar)
            icon.spark:ClearAllPoints()
            icon.spark:SetPoint("TOP", icon.bar:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
            icon.spark:SetPoint("BOTTOM", icon.bar:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
            icon.barCooldown:ClearAllPoints()
            icon.barCooldown:SetPoint("TOPRIGHT", icon.bar, "TOPRIGHT", 0, 0)
            icon.barCooldown:SetSize(math.min(width, size * 1.6), size)
            icon.barCooldown:SetShown(not trace.nameBar)
            local offsetX = Number(db.textOfsX, 3, 1, 30)
            local fontSize = math.max(6, math.floor(12 * Number(db.textScale, 1, .5, 1) + .5))
            NameFont(icon.label, db, fontSize)
            icon.label:ClearAllPoints()
            icon.label:SetPoint("LEFT", icon.bar, "LEFT", offsetX, Number(db.textOfsY, 0, -15, 15))
            icon.label:SetWidth(math.max(1, width - offsetX - (trace.nameBar and 2 or 34)))
        else
            icon.bar:SetPoint("TOPLEFT", icon, "TOPLEFT", size+2, 0)
            icon.bar:SetPoint("BOTTOMRIGHT")
            NameFont(icon.label, trace.db, Number(trace.db.nameFontSize, 12, 6, 32))
            icon.label:ClearAllPoints()
            icon.label:SetPoint("LEFT", icon, "LEFT", size+6+Number(trace.db.nameOfsX, 0, -100, 100),
                Number(trace.db.nameOfsY, 0, -100, 100))
            icon.label:SetWidth(trace.itemWidth-size-52)
            icon.barBG:SetColorTexture(unpack(C.bg.input))
            if icon.barBorder then icon.barBorder:Hide(); icon.spark:Hide(); icon.barCooldown:Hide() end
        end
        icon.bar:SetShown(bars)
        icon.label:SetShown(bars)
    end
end

local function SetLabel(icon, row, db, class, trace)
    if not icon.owner:IsShown() and not (icon.label and icon.label:IsShown()) then return end
    local name = row.displayName
    local omni = trace and trace.barIndex
    local color = ClassColor(class)
    if omni then
        -- [STYLE] OmniCD icon names: truncated, optionally class colored.
        icon.owner:SetText(Truncate(name, db.truncateIconName) or "")
        if db.classColor ~= false and color then icon.owner:SetTextColor(color.r, color.g, color.b, 1)
        else icon.owner:SetTextColor(ColorOf(db.nameColor, C.text.highlight)) end
    else
        icon.owner:SetText(name or "")
        if db.nameClassColor == true and color then icon.owner:SetTextColor(color.r, color.g, color.b, 1)
        else icon.owner:SetTextColor(ColorOf(db.nameColor, C.text.dim)) end
    end
    if icon.label and icon.label:IsShown() then
        if omni then
            -- State colors are painted with the timer (Trace:PaintBar).
            icon.label:SetText(Truncate(name, db.truncateStatusBarName) or "…")
            return
        end
        -- [STYLE] The spell stays identifiable by its icon; bars name the party member.
        icon.label:SetText(name or "…")
        if db.nameClassColor == true and color then
            icon.label:SetTextColor(color.r, color.g, color.b, 1)
        else
            icon.label:SetTextColor(ColorOf(db.nameColor, C.text.highlight))
        end
        if db.barClassColor == true and color then
            icon.bar:SetStatusBarColor(color.r, color.g, color.b, 1)
        else
            icon.bar:SetStatusBarColor(unpack(C.status.success))
        end
    end
end

-- [STYLE] OmniCD status bar colors: name / bar / background per active, recharge and inactive state.
function Trace:StateColor(set, key, fallback, class)
    local colors = type(self.db[set]) == "table" and self.db[set] or {}
    local r, g, b, a = ColorOf(colors[key .. "Color"], fallback)
    local use = type(colors.useClassColor) == "table" and colors.useClassColor[key] == true
    local color = use and ClassColor(class)
    if color then r, g, b = color.r, color.g, color.b end
    return r, g, b, a
end

function Trace:PaintBar(icon, class, state, fraction)
    if not (self.barIndex and self.bars and icon.bar) then return end
    local db = self.db
    local function Pick(set, key, fallback) return self:StateColor(set, key, fallback, class) end
    icon.label:SetTextColor(Pick("textColors", state, {1, 1, 1, 1}))
    local cooling = state ~= "inactive"
    if self.nameBar then
        icon.barBG:SetColorTexture(0, 0, 0, 0)
        icon.spark:Hide()
        return
    end
    icon.bar:SetStatusBarColor(Pick("barColors", state, {0, 1, 0, 1}))
    -- OmniCD has no inactive background: a ready bar is full and uses the bar color.
    if cooling then icon.barBG:SetColorTexture(Pick("bgColors", state, {0, 0, 0, .5}))
    else icon.barBG:SetColorTexture(Pick("barColors", "inactive", {0, 1, 0, 1})) end
    icon.spark:SetShown(cooling and db.hideSpark ~= true and fraction ~= nil and fraction > 0 and fraction < 1)
end

-- [12.0.1] Hidden party timers (KiraUI 1.26 principle, new code). A secret use stamp from
-- Sensor.lua moves status-bar fills; a grey cover and a clipped strip of countdown numbers ride
-- on those fills, so the engine draws the remaining time and Lua never reads it.
-- Fill of a bar with range (base, base + 1) and value c is (1 + elapsed steps) / 255.
local meter, metrics, strips = nil, {}, {}

local function StringHeight(text)
    meter:SetText(text)
    local height = meter:GetStringHeight()
    if Secret(height) or type(height) ~= "number" or height <= 0 then return nil end
    return height
end

local function PixelsPerUnit(region)
    local scale = region:GetEffectiveScale()
    local _, height
    if GetPhysicalScreenSize then _, height = GetPhysicalScreenSize() end
    if not PublicNumber(scale) or not PublicNumber(height) or scale <= 0 or height <= 0 then return nil end
    return scale * height / 768
end

-- Line step and glyph height of a multi-line strip; the step is nudged to whole screen pixels.
local function LineMetrics(font, size, flags, ppu)
    local key = table.concat({tostring(font), tostring(size), tostring(flags), ppu and string.format("%.4f", ppu) or "-"}, "|")
    local cached = metrics[key]
    if cached then return cached[1], cached[2], cached[3] end
    if not meter then
        local frame = CreateFrame("Frame", nil, UIParent)
        frame:SetSize(1, 1)
        frame:SetPoint("CENTER")
        frame:SetAlpha(0)
        meter = frame:CreateFontString(nil, "OVERLAY")
        meter:SetPoint("CENTER")
    end
    meter:SetFont(font, size, flags)
    meter:SetSpacing(0)
    local nine = ("0\n"):rep(8) .. "0"
    local one, all = StringHeight("0"), StringHeight(nine)
    if not (one and all and all > one) then return nil end
    local step, gap = (all - one) / 8, 0
    local pixels = ppu and step * ppu
    if pixels and math.abs(pixels - math.floor(pixels + .5)) > .02 then
        local spacing = (math.ceil(pixels) - pixels) / ppu
        meter:SetSpacing(spacing)
        local wide = StringHeight(nine)
        local got = wide and (wide - one) / 8 * ppu
        if got and math.abs(got - math.floor(got + .5)) <= .02 then step, gap = got / ppu, spacing end
        meter:SetSpacing(0)
    end
    metrics[key] = {step, one, gap}
    return step, one, gap
end

local function StripText(seconds)
    local text = strips[seconds]
    if not text then
        local lines = {}
        for left = seconds, 1, -1 do lines[#lines+1] = Clock(left) end
        text = table.concat(lines, "\n")
        strips[seconds] = text
    end
    return text
end

local function Transparent(bar)
    bar:SetStatusBarTexture(SL.Textures.flat)
    bar:SetStatusBarColor(0, 0, 0, 0)
    bar:SetOrientation("VERTICAL")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    bar:EnableMouse(false)
    return bar
end

local function HiddenLayer(icon)
    if icon.hidden then return icon.hidden end
    local layer = {gate={}, veil={}, grey={}, cover={}, coverBG={}, pos={}, text={}, strip={}, names={}}
    layer.root = CreateFrame("Frame", nil, icon)
    layer.root:SetAllPoints(icon)
    layer.root:EnableMouse(false)
    layer.win = CreateFrame("Frame", nil, layer.root)
    layer.win:SetClipsChildren(true)
    layer.win:EnableMouse(false)
    for k = 1, 2 do
        layer.gate[k] = Transparent(CreateFrame("StatusBar", nil, layer.root))
        local veil = CreateFrame("Frame", nil, layer.root)
        veil:SetClipsChildren(true)
        veil:EnableMouse(false)
        veil:SetAlpha(0)
        layer.veil[k] = veil
        local name = CreateFrame("Frame", nil, layer.root)
        name:SetClipsChildren(true)
        name:SetAllPoints(veil)
        name:EnableMouse(false)
        name.text = name:CreateFontString(nil, "OVERLAY")
        name.text:SetWordWrap(false)
        layer.names[k] = name
        layer.grey[k] = veil:CreateTexture(nil, "ARTWORK")
        layer.grey[k]:SetDesaturated(true)
        local cover = CreateFrame("StatusBar", nil, veil)
        cover:SetStatusBarTexture(SL.Textures.flat)
        cover:EnableMouse(false)
        layer.coverBG[k] = cover:CreateTexture(nil, "BACKGROUND")
        layer.coverBG[k]:SetAllPoints()
        layer.cover[k] = cover
        layer.pos[k] = Transparent(CreateFrame("StatusBar", nil, layer.root))
        local text = CreateFrame("Frame", nil, layer.win)
        text:SetAllPoints(layer.win)
        text:SetAlpha(0)
        layer.text[k] = text
        layer.strip[k] = text:CreateFontString(nil, "OVERLAY")
    end
    icon.hidden = layer
    return layer
end

local function HideHidden(icon)
    if icon.hidden then icon.hidden.root:Hide() end
    icon.cooldown:SetAlpha(1)
    icon.timerLayer:SetAlpha(1)
end

-- Rebuilt only when the timer length, icon size, text or bar style changes.
function Trace:DressHidden(icon, timer, class)
    local layer = HiddenLayer(icon)
    local ppu = PixelsPerUnit(icon)
    local quick = table.concat({self.generation or 0, timer.seconds, tostring(class), ppu or 0}, "|")
    if layer.quick == quick then return layer end
    layer.quick = quick
    local font, fontSize, flags = icon.text:GetFont()
    font, fontSize = font or SL.Font.path, fontSize or 12
    local step, one, gap = LineMetrics(font, fontSize, flags, ppu)
    local point, relative, relativePoint, x, y = icon.text:GetPoint(1)
    local omni = self.barIndex ~= nil and self.bars
    local covered = self.bars and not self.nameBar
    -- OmniCD "reverse fill" and DDingUI bars show remaining time; plain OmniCD fill grows.
    local remaining = not omni or self.db.reverseFill ~= false
    local bar, bg
    if covered then
        local color = self.db.barClassColor == true and ClassColor(class)
        if omni then bar = {self:StateColor("barColors", "active", {0, 1, 0, 1}, class)}
        elseif color then bar = {color.r, color.g, color.b, 1}
        else bar = {unpack(C.status.success)} end
        bg = omni and {self:StateColor("bgColors", "active", {0, 0, 0, .5}, class)} or {unpack(C.bg.input)}
    end
    local key = table.concat({timer.seconds, timer.u, self.size, self.itemWidth, tostring(step), tostring(one),
        tostring(gap), tostring(point), tostring(relativePoint), x or 0, y or 0, tostring(covered),
        tostring(remaining), tostring(font), fontSize, table.concat(bar or {}, ","), table.concat(bg or {}, ",")}, "|")
    layer.step = step
    if layer.key == key then return layer end
    layer.key = key
    local seconds, u, size = timer.seconds, timer.u, self.size
    -- One second moves the cover a full icon height, so it leaves the icon in one step at zero.
    local jump = size + 4
    local right = type(point) == "string" and point:find("RIGHT") ~= nil
    local level = icon.cooldown:GetFrameLevel()
    layer.win:ClearAllPoints()
    layer.win:SetPoint(point or "CENTER", relative or icon, relativePoint or "CENTER", x or 0, y or 0)
    layer.win:SetSize(right and fontSize * 3 or math.max(size + 6, fontSize * 3), step and math.min(one, step) or 1)
    layer.win:SetFrameLevel(level + 5)
    for k = 1, 2 do
        local gate, veil, cover, pos, strip = layer.gate[k], layer.veil[k], layer.cover[k], layer.pos[k], layer.strip[k]
        gate:ClearAllPoints()
        gate:SetPoint("BOTTOM", icon, "BOTTOM", 0, -(seconds - 1 + u) * jump)
        gate:SetSize(1, 255 * u * jump)
        local edge = gate:GetStatusBarTexture()
        veil:ClearAllPoints()
        veil:SetPoint("BOTTOM", edge, "TOP", 0, -3)
        veil:SetPoint("TOP", edge, "TOP", 0, (seconds - 1) * jump + size + 1)
        veil:SetWidth(self.itemWidth + 4)
        veil:SetFrameLevel(level + 1)
        layer.grey[k]:SetAllPoints(icon.texture)
        layer.grey[k]:SetTexCoord(.07, .93, .07, .93)
        cover:SetShown(covered)
        if covered then
            cover:ClearAllPoints()
            cover:SetAllPoints(icon.bar)
            cover:SetFrameLevel(level + 1)
            cover:SetOrientation("HORIZONTAL")
            -- The fill is the elapsed part: dark from the right for remaining time, colored otherwise.
            cover:SetReverseFill(remaining)
            cover:SetStatusBarColor(unpack(remaining and bg or bar))
            layer.coverBG[k]:SetColorTexture(unpack(remaining and bar or bg))
        end
        pos:ClearAllPoints()
        if step then
            local anchor = right and "BOTTOMRIGHT" or "BOTTOM"
            pos:SetPoint(anchor, layer.win, anchor, 0, -(seconds - 1 + u) * step)
            pos:SetSize(1, 255 * u * step)
            strip:SetFont(font, fontSize, flags)
            strip:SetSpacing(gap)
            strip:SetTextColor(unpack(C.text.highlight))
            strip:SetJustifyH(right and "RIGHT" or "CENTER")
            strip:ClearAllPoints()
            strip:SetPoint(anchor, pos:GetStatusBarTexture(), right and "TOPRIGHT" or "TOP", 0, 0)
            strip:SetText(StripText(seconds))
        end
        layer.text[k]:SetFrameLevel(level + 5)
        layer.names[k]:SetFrameLevel(level + 4)
    end
    return layer
end

function Trace:DrawHidden(icon, id, timer, class, n, now)
    local layer = self:DressHidden(icon, timer, class)
    local fx = self.fx or self.db
    local numbers = layer.step ~= nil and fx.showNumbers ~= false
    local span = 255 * timer.u
    for k = 1, 2 do
        local slot = timer.slots[k]
        local veil, text = layer.veil[k], layer.text[k]
        -- [12.0.1] Active name color rides the same clipped geometry as the hidden cooldown.
        local name = layer.names[k]
        name:SetShown(self.barIndex ~= nil and self.bars and icon.label:IsShown())
        if name:IsShown() then
            name.text:SetFont(icon.label:GetFont())
            name.text:SetAllPoints(icon.label)
            name.text:SetJustifyH(icon.label:GetJustifyH())
            name.text:SetText(icon.label:GetText())
            name.text:SetTextColor(self:StateColor("textColors", "active", C.text.highlight, class))
        end
        if Secret(slot.v) or slot.v ~= 0 then
            local base = (Sensor.CODES - (n - slot.epoch) / timer.u) / 255
            for _, bar in ipairs({layer.gate[k], layer.pos[k]}) do
                bar:SetMinMaxValues(base, base + 1)
                bar:SetValue(slot.c)
            end
            local cover = layer.cover[k]
            if cover:IsShown() then
                local start = 1 - (now - slot.epoch) / span
                cover:SetMinMaxValues(start, start + timer.seconds / span)
                cover:SetValue(slot.c)
            end
            layer.grey[k]:SetTexture(SpellTexture(id))
            veil:SetAlpha(slot.v)
            name:SetAlpha(slot.v)
            if numbers then text:SetAlpha(slot.v) else text:SetAlpha(0) end
        else
            veil:SetAlpha(0)
            name:SetAlpha(0)
            text:SetAlpha(0)
        end
    end
    icon.cooldown:SetAlpha(timer.pub)
    icon.timerLayer:SetAlpha(timer.pub)
    layer.root:Show()
end

function Trace:OnInitialize()
    self.db = self:LayoutDB()
    self.ledger = self.ledger or {}
    self.rows = self.rows or {}
end

function Trace:LayoutDB()
    local root = ns.db.profile.CooldownTrace
    if self.barIndex then return root.extraBars["bar" .. self.barIndex] end
    return root[self.kind]
end

-- [REFACTOR] Frame 0 and the extra bars read the OmniCD frame assignment; a category engine lists its own selection.
function Trace:Spells(class)
    if self.kind == "common" then return ns.SkillTracker:Spells(0, class) end
    if self.barIndex then return ns.SkillTracker:Spells(self.barIndex, class) end
    local db = ns.db.profile.CooldownTrace[self.kind]
    return (db.spells or Data[self.kind] or {})[class] or {}
end

function Trace:RowSpells(row)
    local result = {}
    local observed = self.ledger[row.guid] or {}
    for _, id in ipairs(self:Spells(row.class)) do
        local specs = Data.specs[id]
        if row.isPlayer or not row.specFiltering or not specs or (row.specID and specs[row.specID])
            or (not row.specID and observed[id]) then result[#result+1] = id end
    end
    return result
end

function Trace:CreateRow(token)
    local row = CreateFrame("Frame", nil, self.frame)
    row.unit, row.icons, row.auras = token, {}, {}
    for i = 1, ICONS do row.icons[i] = Icon(row, 30) end
    row.previewActive = Icon(row, 30)
    row.previewActive.cooldown:SetReverse(true)
    row.previewActive.glow = ActiveGlow(row.previewActive, self.fx or self.db)
    row.observer = CreateFrame("Frame")
    row.observer:SetScript("OnEvent", function(_, event, _, _, spellID)
        if not self.running or self.preview or not row.guid then return end
        if event == "UNIT_AURA" then
            self:ScanAuras(row)
        elseif not Secret(spellID) and type(spellID) == "number" then
            if Sensor.available and not IsInRaid() and not row.isPlayer then return end
            self:Record(row, spellID, GetTime())
        end
    end)
    if self.running then
        row.observer:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", token)
        row.observer:RegisterUnitEvent("UNIT_AURA", token)
    end
    row:Hide()
    return row
end

function Trace:CreateFrame()
    if self.frame then return end
    self:OnInitialize()
    local frame = CreateFrame("Frame", "DDingToolKit_" .. self.moduleName .. "Frame", UIParent)
    self.frame = frame
    frame:SetClampedToScreen(true)
    frame:EnableMouse(false)
    if self.barIndex then frame:SetMovable(true) end
    for index, token in ipairs(TOKENS) do self.rows[index] = self:CreateRow(token) end
    frame:Hide()
end

-- [REFACTOR] OmniCD extra bar fields map onto the shared layout engine.
function Trace:ConfigureBar(db)
    local scale = Number(db.scale, .6, .2, 2)
    local size = Number(db.pixelSize, BASE_ICON * scale, 8, 96) / scale
    self.vertical = db.layout ~= "horizontal"
    -- OmniCD offers the status bar timer only in the vertical layout.
    self.bars = self.vertical and db.progressBar ~= false
    self.nameBar = self.bars and db.nameBar == true
    self.combined = db.unitBar ~= true
    self.columns = math.floor(Number(db.columns, 15, 1, 30))
    self.gapX, self.gapY = Number(db.paddingX, -1, -1, 20), Number(db.paddingY, -1, -1, 20)
    self.rowSpacing, self.align, self.sortOrder = 0, "LEFT", nil
    self.grow = db.growUpward and "UP" or "DOWN"
    self.growLeft = self.combined and db.growLeft == true
    self.sortBy, self.sortDirection = db.sortBy, db.sortDirection
    self.attached = not self.combined and not self.preview
    self.barAnchor = BAR_POINTS[db.anchor] and db.anchor or "TOPRIGHT"
    self.barAttach = BAR_POINTS[db.attach] and db.attach or "TOPLEFT"
    self.offsetX, self.offsetY = Number(db.offsetX, 0, -500, 500), Number(db.offsetY, 0, -500, 500)
    self.statusWidth = Number(db.statusBarWidth, 205, 50, 300)
    self.itemWidth = self.bars and size + self.statusWidth or size
    self.showNames = self.combined and not self.bars and db.showName ~= false
    -- [STYLE] Names overlay the grid; Y spacing measures icon edges only.
    self.itemHeight = size
    self.hidePlayer = db.showPlayer == false
    self.size = size
    self.width = self:GridWidth(self.columns)
    return scale
end

function Trace:GridWidth(total)
    local lines = self.vertical and math.max(1, math.ceil(total / self.columns)) or math.min(self.columns, math.max(total, 1))
    if not self.barIndex then lines = self.columns end
    return math.max(1, lines * (self.itemWidth + self.gapX) - self.gapX)
end

function Trace:GridHeight(total)
    local lines
    if self.barIndex and self.vertical then lines = math.min(self.columns, math.max(total, 1))
    else lines = math.max(1, math.ceil(total / self.columns)) end
    return math.max(1, lines * (self.itemHeight + self.gapY) - self.gapY)
end

function Trace:ApplySettings()
    self:CreateFrame()
    if InCombatLockdown() then self.pending = true; self:RefreshRoster(); return end
    self.suspended = false
    self.pending = Restricted()
    -- Hidden timer layers re-dress after any layout change.
    self.generation = (self.generation or 0) + 1
    self.db = self:LayoutDB()
    -- [REFACTOR] Every frame owns its effect and context options (bars adopted frame 0's values once).
    self.fx = self.db
    local db, fx = self.db, self.fx
    -- [12.0.1] Allocate raid rows only as needed, outside combat; tokens never change under aura slots.
    if IsInRaid() and fx.showInRaid ~= false then
        for index = 1, math.min(GetNumGroupMembers(), 40) do
            if not self.rows[#TOKENS + index] then
                self.rows[#TOKENS + index] = self:CreateRow("raid" .. index)
            end
        end
    end
    local scale
    if self.barIndex then
        scale = self:ConfigureBar(db)
    else
        local size = Number(db.iconSize, 30, 20, 48)
        scale = Number(db.scale, 1, .5, 1.5)
        if db.pixelSize ~= nil then size = Number(db.pixelSize, size * scale, 8, 96) / scale end
        self.bars, self.combined = db.displayStyle == "bars", db.memberLayout == "all"
        self.nameBar, self.vertical, self.growLeft, self.hidePlayer = false, false, false, false
        self.showNames, self.statusWidth = nil, nil
        self.columns = self.bars and 1 or math.floor(Number(db.columns, 6, 1, 12))
        self.gapX, self.gapY = Number(db.gapX, 4, 0, 20), Number(db.gapY, 4, 0, 20)
        self.rowSpacing = Number(db.rowSpacing, 6, 0, 40)
        self.align, self.grow, self.sortOrder = db.align, db.grow, db.sortOrder
        self.attached = db.attachTo == "party" and not self.combined and not self.preview
        self.attachSide = ATTACH_POINTS[db.attachSide] and db.attachSide or "RIGHT"
        self.offsetX, self.offsetY = Number(db.offsetX, 0, -500, 500), Number(db.offsetY, 0, -500, 500)
        self.itemWidth = self.bars and math.max(size+60, Number(db.barWidth, 220, 140, 400)) or size
        self.itemHeight = size
        self.size = size
        self.width = self.columns * (self.itemWidth + self.gapX) - self.gapX
    end
    local size, width = self.size, self.width
    self.frame:SetScale(scale)
    local p = self.db.position
    self.frame:ClearAllPoints()
    self.frame:SetPoint(p.point or "CENTER", UIParent, p.relativePoint or "CENTER", p.x or 0, p.y or 0)
    for _, row in ipairs(self.rows) do
        row.layoutCount = nil
        row:SetSize(width, size + 10)
        for _, icon in ipairs(row.icons) do
            ConfigureIcon(icon, self)
            ConfigureCooldown(icon.cooldown, fx)
            if self.barIndex and self.bars and not self.nameBar then
                -- The bar end shows the timer; the icon keeps only its swipe.
                icon.cooldown:SetHideCountdownNumbers(true)
                icon.barCooldown:SetHideCountdownNumbers(fx.showNumbers == false)
            end
            if fx.useGlow == true and not icon.useGlow then
                icon.useGlow = ActiveGlow(icon, fx, true)
                icon.useGlow:SetFrameLevel(icon.cooldown:GetFrameLevel() + 30)
            end
            if icon.useGlow then ConfigureGlow(icon.useGlow, fx, true); icon.useGlow:Hide() end
        end
        row.previewActive:SetSize(size, size)
        ConfigureBorder(row.previewActive, fx)
        ConfigureCooldown(row.previewActive.cooldown, fx)
        ConfigureGlow(row.previewActive.glow, fx)
    end
    self:UpdateBarAnchor()
    if self.preview then self:RenderPreview() else self:RefreshRoster() end
end

-- [STYLE] OmniCD unlocked extra bar: black-to-clear name tab above the bar; drag it to move.
function Trace:UpdateBarAnchor()
    if not self.barIndex then return end
    local show = self.combined and self.preview == true
    if show and not self.barTab then
        local tab = CreateFrame("Frame", nil, self.frame)
        tab:SetHeight(15)
        tab:SetPoint("BOTTOMLEFT", self.frame, "TOPLEFT", 0, 0)
        tab:EnableMouse(true)
        tab:RegisterForDrag("LeftButton")
        tab.bg = tab:CreateTexture(nil, "BACKGROUND")
        tab.bg:SetAllPoints()
        tab.bg:SetColorTexture(1, 1, 1, 1)
        if tab.bg.SetGradient and CreateColor then
            tab.bg:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, 1), CreateColor(0, 0, 0, .05))
        else
            tab.bg:SetColorTexture(0, 0, 0, .6)
        end
        tab.text = Text(tab, 10, {1, .824, 0, 1})
        tab.text:SetPoint("LEFT", tab, "LEFT", 4, 0)
        tab:SetScript("OnDragStart", function()
            if InCombatLockdown() then return end
            self.frame:StartMoving()
        end)
        tab:SetScript("OnDragStop", function()
            self.frame:StopMovingOrSizing()
            -- The saved profile position stays the only source (no client layout cache).
            if self.frame.SetUserPlaced then self.frame:SetUserPlaced(false) end
            local point, _, relativePoint, x, y = self.frame:GetPoint(1)
            if not point or Secret(x) or Secret(y) then return end
            local p = self.db.position
            p.point, p.relativePoint = point, relativePoint or point
            p.x, p.y = math.floor((x or 0) + .5), math.floor((y or 0) + .5)
        end)
        self.barTab = tab
    end
    if self.barTab then
        self.barTab:SetWidth(math.max(self.itemWidth, 60))
        self.barTab.text:SetText(ns.SkillTracker:BarName(self.barIndex))
        self.barTab:SetShown(show)
    end
end

function Trace:RefreshAnchors()
    if not self.attached or InCombatLockdown() then return end
    if self.barIndex then
        -- [STYLE] OmniCD unit bar: the bar's anchor point meets the unit frame's attachment point.
        for _, row in ipairs(self.rows) do
            local anchor = PartyAnchor(row.unit)
            row.anchor = anchor
            row:ClearAllPoints()
            if anchor then row:SetPoint(self.barAnchor, anchor, self.barAttach, self.offsetX, self.offsetY) end
        end
        return
    end
    local p = ATTACH_POINTS[self.attachSide]
    local point, dy = p[1], 0
    if self.attachSide == "LEFT" or self.attachSide == "RIGHT" then
        -- [STYLE] Centre the first icon line on the unit frame; extra lines grow away from it.
        local half = self.size / 2
        local up = self.grow == "UP"
        point, dy = (up and "BOTTOM" or "TOP") .. point, up and -half or half
    end
    for _, row in ipairs(self.rows) do
        local anchor = PartyAnchor(row.unit)
        row.anchor = anchor
        row:ClearAllPoints()
        if anchor then row:SetPoint(point, anchor, p[2], self.offsetX, self.offsetY + dy) end
    end
end

function Trace:EnsureContainer(row)
    if Restricted() then return end
    if C_AddOns and C_AddOns.LoadAddOn then
        local ok, loaded = pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
        if not ok or not loaded then return end
    end
    if not row.container then
        row.container = CreateFrame("Frame", nil, row)
        row.container:SetAllPoints(row)
        row.container:EnableMouse(false)
        row.effects = {}
    end
    row.auraUnavailable = false
    local fx = self.fx or self.db
    for _, id in ipairs(self:RowSpells(row)) do
        if not row.effects[id] then
            -- [12.0.1] An addon-owned proxy follows the icon; secret slot visibility stays in the engine.
            local proxy = CreateFrame("Frame", nil, UIParent)
            proxy:SetSize(self.size, self.size)
            proxy:EnableMouse(false)
            proxy:Hide()
            local ok = pcall(function()
                local container = CreateFrame("AuraContainer", nil, proxy, "CustomAuraContainerTemplate")
                container:SetSize(1, 1)
                container:SetPoint("CENTER", proxy, "CENTER")
                container:EnableMouse(false)
                local map = {}
                for _, auraID in ipairs(Data.auraIDs[id] or {id}) do map[auraID] = true end
                container:AddAuraSlot("effect", "HELPFUL", {
                    candidateFilters = {includeSpellIDs = map},
                    initializeFrame = function(button)
                        button:SetAllPoints(proxy)
                        button:EnableMouse(false)
                        local texture = button:CreateTexture(nil, "ARTWORK")
                        texture:SetAllPoints()
                        texture:SetTexCoord(.07, .93, .07, .93)
                        texture:SetTexture(SpellTexture(id))
                        local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
                        cooldown:SetAllPoints()
                        cooldown:SetDrawEdge(false)
                        cooldown:SetReverse(true)
                        ConfigureCooldown(cooldown, fx)
                        button:SetDurationCooldown(cooldown)
                        button.glow = ActiveGlow(button, fx, false, self.size)
                        proxy.visual, proxy.durationCooldown = button, cooldown
                    end,
                })
                container:SetUnit(row.unit)
                container:UpdateAllAuras()
            end)
            if ok then
                proxy:SetParent(row.container)
                row.effects[id] = proxy
            else
                proxy:Hide()
                row.auraUnavailable = true
            end
        end
        local proxy = row.effects[id]
        if proxy and proxy.visual then
            ConfigureCooldown(proxy.durationCooldown, fx)
            ConfigureGlow(proxy.visual.glow, fx, false, not ns.SkillTracker:Glow(id), self.size)
        end
    end
end

function Trace:RefreshRoster()
    if self.preview or not self.size then return end
    local inRaid = IsInRaid()
    local fx = self.fx or self.db
    if inRaid and fx.showInRaid ~= false and not InCombatLockdown()
        and #self.rows < #TOKENS + math.min(GetNumGroupMembers(), 40) then
        self:ApplySettings()
        return
    end
    local inDelve = C_PartyInfo and (C_PartyInfo.IsDelveInProgress() or C_PartyInfo.IsDelveComplete())
    local allowed = IsInGroup() and GetNumGroupMembers() > 1
        and (inDelve and fx.showInDelve ~= false
            or not inDelve and (inRaid and fx.showInRaid ~= false or not inRaid and fx.showInParty ~= false))
    self:RefreshAnchors()
    local count, retained = 0, {}
    for index, row in ipairs(self.rows) do
        row.previewActive:Hide()
        local active = allowed and ((inRaid and index > #TOKENS) or (not inRaid and index <= #TOKENS))
        local guid = active and UnitGUID(row.unit)
        local same = UnitIsUnit(row.unit, "player")
        row.isPlayer = not Secret(same) and same == true
        if Secret(guid) or type(guid) ~= "string" then guid = nil end
        local _, class = UnitClass(row.unit)
        if Secret(class) or type(class) ~= "string" then class = nil end
        local name = guid and UnitName(row.unit)
        row.displayName = not Secret(name) and type(name) == "string" and name or nil
        -- OmniCD "Show Player" can leave the player's own spells off an extra bar.
        if guid and class and self.running and #self:Spells(class) > 0 and not (self.hidePlayer and row.isPlayer) then
            count = count + 1
            retained[guid] = true
            local changed = row.guid ~= guid or row.class ~= class
            if changed then
                row.auras = {}
                row.guid, row.class = guid, class
                row.auraUnavailable = true
            end
            local spec, filtering = ns.SkillTracker:UnitSpec(row.unit, guid, class, row.isPlayer)
            changed = changed or row.specID ~= spec
            row.specID, row.specFiltering = spec, filtering
            if changed then self:ScanAuras(row, true) end
            row:Show()
            self:EnsureContainer(row)
        else
            row.guid, row.class, row.auras, row.specID = nil, nil, {}, nil
            row:Hide()
        end
    end
    for guid in pairs(self.ledger) do
        if not retained[guid] then self.ledger[guid] = nil end
    end
    local shown = self.running and count > 0 and not self.suspended
    self.frame:SetShown(shown)
    -- [12.0.1] Party rows (not raid, not the player) ask the hidden-use sensors for their spells.
    local wants
    if shown and not inRaid then
        wants = {}
        for index, row in ipairs(self.rows) do
            if index <= #TOKENS and row.guid and not row.isPlayer then
                for _, id in ipairs(self:RowSpells(row)) do
                    wants[row.unit] = wants[row.unit] or {}
                    wants[row.unit][id] = true
                end
            end
        end
    end
    Sensor:Track(self, wants)
    self.containerUnavailable = false
    for _, row in ipairs(self.rows) do
        if row.guid and (not row.container or row.auraUnavailable) then self.containerUnavailable = true end
    end
    self:UpdateCooldowns()
end

function Trace:Record(row, id, started)
    if not row.guid or not PublicNumber(id) or not PublicNumber(started) then return end
    id = Data.castIDs[id] or id
    local found
    for _, candidate in ipairs(self:Spells(row.class)) do
        if candidate == id then found = true; break end
    end
    if not found then return end
    local spells = self.ledger[row.guid]
    if not spells then spells = {}; self.ledger[row.guid] = spells end
    local previous = spells[id]
    if previous and started - previous.started < 1 then return end
    spells[id] = {started=started, seconds=Sensor.Seconds(id)}
    -- A public use replaces any hidden stamp of the same spell.
    Sensor:Public(row.unit, id, started)
    self:UpdateCooldowns()
end

-- [12.0.1] Public rising edge of a party buff (Sensor.lua), recorded like a public cast.
function Trace:SensedUse(unit, id, started)
    for _, row in ipairs(self.rows) do
        if row.unit == unit and row.guid then self:Record(row, id, started) end
    end
end

function Trace:ScanAuras(row, baseline)
    if Sensor.available and not IsInRaid() and not row.isPlayer then return end
    if not row.guid or not C_Secrets or not C_Secrets.GetSpellAuraSecrecy
        or not C_UnitAuras.GetUnitAuraBySpellID then return end
    for _, id in ipairs(self:RowSpells(row)) do
        for _, auraID in ipairs(Data.auraIDs[id] or {id}) do
            local ok, secrecy = pcall(C_Secrets.GetSpellAuraSecrecy, auraID)
            -- Contextual/secret auras belong to the engine container alone.
            if ok and not Secret(secrecy) and secrecy == 0 then
                local read, aura = pcall(C_UnitAuras.GetUnitAuraBySpellID, row.unit, auraID)
                if read and not Secret(aura) then
                    local present = type(aura) == "table"
                    if present and not row.auras[auraID] and not baseline then
                        local source, duration, expires = aura.sourceUnit, aura.duration, aura.expirationTime
                        if not Secret(source) and type(source) == "string"
                            and PublicNumber(duration) and PublicNumber(expires) and duration > 0
                        then
                            local same = UnitIsUnit(source, row.unit)
                            local start = expires - duration
                            if not Secret(same) and same and start <= GetTime() and start >= 0 then
                                self:Record(row, id, start)
                            end
                        end
                    end
                    row.auras[auraID] = present
                end
            end
        end
    end
end

-- [REFACTOR] OmniCD sort keys (Modules/Party/ExtraBars.lua sorters 3, 4, 9, 10); ties stay deterministic.
local function ByPriority(a, b)
    if a.priority ~= b.priority then return a.priority > b.priority end
    if a.class ~= b.class then return a.class < b.class end
    if a.id ~= b.id then return a.id < b.id end
    return a.order < b.order
end

local function ByClass(a, b)
    if a.class ~= b.class then return a.class < b.class end
    if a.priority ~= b.priority then return a.priority > b.priority end
    if a.id ~= b.id then return a.id < b.id end
    return a.order < b.order
end

local function Remaining(base)
    return function(a, b)
        if a.cooling and b.cooling then
            if a.ends ~= b.ends then return a.ends < b.ends end
            return base(a, b)
        elseif not a.cooling and not b.cooling then
            return base(a, b)
        end
        return b.cooling -- ready spells first
    end
end

local SORTERS = {priority=ByPriority, class=ByClass,
    remaining_priority=Remaining(ByPriority), remaining_class=Remaining(ByClass)}

local function PriorityOrder(list)
    local rank = {}
    for index, id in ipairs(list) do rank[id] = rank[id] or index end
    table.sort(list, function(a, b)
        local pa, pb = ns.SkillTracker:Priority(a), ns.SkillTracker:Priority(b)
        if pa ~= pb then return pa > pb end
        return rank[a] < rank[b]
    end)
    return list
end

-- Public end time only: native player cooldowns without public numbers sort after known timers.
function Trace:CooldownKey(row, id, observed, now)
    if row.isPlayer then
        local ok, info = pcall(C_Spell.GetSpellCooldown, id)
        if ok and not Secret(info) and type(info) == "table" and not Secret(info.isActive) and info.isActive == true then
            if PublicNumber(info.startTime) and PublicNumber(info.duration) then return true, info.startTime + info.duration end
            return true, math.huge
        end
    end
    local entry = observed[id]
    if entry and entry.seconds and entry.started + entry.seconds > now then return true, entry.started + entry.seconds end
    return false, 0
end

function Trace:OrderSlots(plans, now)
    local sorter = SORTERS[self.sortBy] or ByPriority
    local timed = self.sortBy == "remaining_priority" or self.sortBy == "remaining_class"
    local items = {}
    for order, row in ipairs(self.rows) do
        local entries = plans[row]
        if entries then
            local observed = self.ledger[row.guid] or {}
            for index, id in ipairs(entries) do
                local item = {row=row, index=index, id=id, class=row.class or "", order=order,
                    priority=ns.SkillTracker:Priority(id), cooling=false, ends=0}
                if timed then item.cooling, item.ends = self:CooldownKey(row, id, observed, now) end
                items[#items+1] = item
            end
        end
    end
    if self.sortDirection == "dsc" then
        table.sort(items, function(a, b) return sorter(b, a) end)
    else
        table.sort(items, sorter)
    end
    local slots = {}
    for slot, item in ipairs(items) do
        slots[item.row] = slots[item.row] or {}
        slots[item.row][item.index] = slot - 1
    end
    self.slots = slots
end

function Trace:UpdateCooldowns()
    if self.preview or self.suspended or not self.size then return end
    local now, offset, db = GetTime(), 0, self.db
    local clock = Sensor.Now()
    local fx = self.fx or db
    local recent = not self.barIndex and self.sortOrder ~= "spell"
    local plans, total = {}, 0
    for _, row in ipairs(self.rows) do
        if row.guid then
            local entries = {}
            local observed = self.ledger[row.guid] or {}
            local candidates = self:RowSpells(row)
            for _, id in ipairs(candidates) do
                if (row.isPlayer and IsPlayerSpell(id)) or (not row.isPlayer and observed[id]) then
                    entries[#entries+1] = id
                end
            end
            if recent then
                table.sort(entries, function(a,b)
                    local at, bt = observed[a] and observed[a].started or -1, observed[b] and observed[b].started or -1
                    return at > bt or (at == bt and a < b)
                end)
            end
            -- [REFACTOR] Keep unobserved selections listed after the existing recent-use order.
            if not row.isPlayer then
                for _, id in ipairs(candidates) do
                    if not observed[id] then entries[#entries+1] = id end
                end
            end
            -- [REFACTOR] Spell order and extra bars follow the OmniCD priority (type or per spell).
            if not recent then PriorityOrder(entries) end
            plans[row] = entries
            total = total + #entries
        end
    end
    self.totalSlots = total
    self.slots = nil
    if self.barIndex and self.combined then
        self.width = self:GridWidth(total)
        self:OrderSlots(plans, now)
    end
    local omni = self.barIndex and self.bars
    for _, row in ipairs(self.rows) do
        local entries = plans[row]
        if entries then
            local observed = self.ledger[row.guid] or {}
            offset = self:LayoutRow(row, #entries, offset)
            local targets = {}
            for index, icon in ipairs(row.icons) do
                local id = entries[index]
                -- [REFACTOR] List selections before first use; public casts start the internal timer.
                icon:SetShown(id ~= nil)
                if id then
                    targets[id] = icon
                    SetLabel(icon, row, db, row.class, self)
                    icon.texture:SetTexture(SpellTexture(id))
                    icon.cooldown:Clear()
                    ConfigureCooldown(icon.cooldown, fx)
                    icon.text:SetText("")
                    icon.count:SetText("")
                    if self.bars then
                        icon.bar:SetMinMaxValues(0, 1)
                        icon.bar:SetValue(1)
                        if omni then
                            icon.cooldown:SetHideCountdownNumbers(not self.nameBar or fx.showNumbers == false)
                            icon.barCooldown:Clear()
                        else
                            icon.cooldown:SetDrawSwipe(false)
                        end
                    end
                    local known, cooling, recharge, fraction = false, false, false, nil
                    if row.isPlayer then
                        local ok, info = pcall(C_Spell.GetSpellCooldown, id)
                        local chargeRead, charges = pcall(C_Spell.GetSpellCharges, id)
                        local charged = chargeRead and not Secret(charges) and type(charges) == "table"
                            and PublicNumber(charges.maxCharges) and charges.maxCharges > 0
                        local durationAPI = C_Spell.GetSpellCooldownDuration
                        if charged then
                            ok, info, durationAPI = true, charges, C_Spell.GetSpellChargeDuration
                            if fx.showCharges ~= false and charges.maxCharges > 1 and PublicNumber(charges.currentCharges) then
                                icon.count:SetText(charges.currentCharges)
                            end
                            recharge = PublicNumber(charges.currentCharges) and charges.currentCharges > 0
                        end
                        if ok and not Secret(info) and type(info) == "table" then
                            if not Secret(info.isActive) and info.isActive == true then
                                local read, duration = pcall(durationAPI, id)
                                if read and not Secret(duration) and duration then
                                    icon.cooldown:SetCooldownFromDurationObject(duration)
                                    if omni and not self.nameBar then icon.barCooldown:SetCooldownFromDurationObject(duration) end
                                    if self.bars and icon.bar.SetTimerDuration then
                                        icon.bar:SetTimerDuration(duration, 0, omni and db.reverseFill == false and 0 or 1)
                                    end
                                    known, cooling, fraction = true, true, .5
                                end
                            elseif (charged or (not Data.noEstimate[id]
                                and not Secret(info.isEnabled) and info.isEnabled == true))
                                and not Secret(info.isActive) and info.isActive == false then
                                known = true
                                if self.bars then icon.bar:SetValue(1) end
                            end
                        end
                    end
                    if not known and observed[id] then
                        local entry = observed[id]
                        local remaining = entry.seconds and entry.started + entry.seconds - now
                        if remaining then
                            if remaining > 0 then
                                cooling = true
                                icon.cooldown:SetCooldown(entry.started, entry.seconds)
                                icon.cooldown:SetHideCountdownNumbers(true)
                                if fx.showNumbers ~= false then icon.text:SetText(Clock(remaining)) end
                            end
                            if self.bars then
                                local value = remaining > 0 and remaining or entry.seconds
                                -- OmniCD fill: reverse shrinks the remaining time, normal grows the elapsed time.
                                if omni and db.reverseFill == false and remaining > 0 then value = entry.seconds - remaining end
                                icon.bar:SetMinMaxValues(0, entry.seconds)
                                icon.bar:SetValue(value)
                                fraction = value / entry.seconds
                            end
                            known = true
                        end
                    end
                    SetIconState(icon, known, cooling, fx)
                    self:PaintBar(icon, row.class, cooling and (recharge and "recharge" or "active") or "inactive", fraction)
                end
                local timer = id and not row.isPlayer and Sensor:Timer(row.unit, row.guid, id)
                if timer then self:DrawHidden(icon, id, timer, row.class, clock, now) else HideHidden(icon) end
                if icon.useGlow then
                    -- [12.0.1] Only public cast evidence can trigger this flash, never secret aura visibility.
                    local entry = id and observed[id]
                    local age = entry and now - entry.started
                    icon.useGlow:SetShown(fx.useGlow == true and age ~= nil and age >= 0
                        and age < Number(fx.useGlowDuration, .8, .2, 3))
                end
            end
            for id, proxy in pairs(row.effects or {}) do
                local target = targets[id]
                if target and proxy.target ~= target then
                    proxy.target = target
                    proxy:SetAllPoints(target.texture)
                    proxy:SetFrameLevel(target.cooldown:GetFrameLevel() + 10)
                end
                proxy:SetShown(target ~= nil)
            end
        end
    end
    self:ResizeFrame(offset)
end

function Trace:ResizeFrame(offset)
    if self.barIndex and self.combined then
        self.frame:SetSize(self:GridWidth(offset), self:GridHeight(offset))
        return
    end
    local height = self.combined and math.ceil(offset/self.columns)*(self.itemHeight+self.gapY)-self.gapY or offset
    self.frame:SetSize(self.width, math.max(height, 1))
end

-- Grid offset of one slot: vertical bars fill columns first, horizontal bars fill rows first.
function Trace:SlotOffset(slot, height)
    local major, minor = math.floor(slot / self.columns), slot % self.columns
    local column, line = minor, major
    if self.vertical then column, line = major, minor end
    return column * (self.itemWidth + self.gapX), line * ((height or self.itemHeight) + self.gapY)
end

function Trace:LayoutRow(row, count, offset)
    count = math.min(count, ICONS)
    if self.barIndex and self.combined then
        -- [STYLE] OmniCD extra bar: one grid for every member, grown from the chosen corner.
        local up, left = self.grow == "UP", self.growLeft
        local point = (up and "BOTTOM" or "TOP") .. (left and "RIGHT" or "LEFT")
        row:ClearAllPoints()
        row:SetPoint(point, self.frame, point, 0, 0)
        row:SetSize(self.width, self.size)
        local slots = self.slots and self.slots[row]
        for i, icon in ipairs(row.icons) do
            local x, y = self:SlotOffset(slots and slots[i] or offset + i - 1)
            icon:ClearAllPoints()
            icon:SetPoint(point, row, point, left and -x or x, up and y + self.itemHeight - self.size or -y)
        end
        row:SetShown(count > 0)
        return offset + count
    end
    if self.barIndex and self.attached then
        -- [STYLE] OmniCD unit bar: icons grow away from the anchor corner ("RIGHT" grows left).
        local point = self.barAnchor
        local left, up = point:find("RIGHT") ~= nil, self.grow == "UP"
        if row.layoutCount ~= count then
            row.layoutCount = count
            local shown = math.max(count, 1)
            local columns = self.vertical and math.ceil(shown / self.columns) or math.min(self.columns, shown)
            local lines = self.vertical and math.min(self.columns, shown) or math.ceil(shown / self.columns)
            row:SetSize(math.max(1, columns * (self.itemWidth + self.gapX) - self.gapX),
                math.max(1, lines * (self.size + self.gapY) - self.gapY))
            for i, icon in ipairs(row.icons) do
                local x, y = self:SlotOffset(i - 1, self.size)
                icon:ClearAllPoints()
                icon:SetPoint(point, row, point, left and -x or x, up and y or -y)
            end
        end
        row:SetShown(MatchesUnit(row.anchor, row.unit) and row.guid ~= nil)
        return offset + row:GetHeight()
    end
    if self.combined then
        -- [STYLE] Pack members into one grid without moving their observers or protected aura slots.
        row:ClearAllPoints()
        local up = self.grow == "UP"
        local point = up and "BOTTOMLEFT" or "TOPLEFT"
        row:SetPoint(point, self.frame, point, 0, 0)
        row:SetSize(self.width, self.size)
        for i, icon in ipairs(row.icons) do
            local slot = offset+i-1
            local used = math.min(self.columns, self.totalSlots-math.floor(slot/self.columns)*self.columns)
            local spare = (self.columns-used)*(self.itemWidth+self.gapX)
            local x = self.align == "RIGHT" and spare or self.align == "CENTER" and spare/2 or 0
            icon:ClearAllPoints()
            icon:SetPoint(point, row, point, x+(slot%self.columns)*(self.itemWidth+self.gapX),
                (up and self.itemHeight-self.size or 0)+(up and 1 or -1)*math.floor(slot/self.columns)*(self.itemHeight+self.gapY))
        end
        row:SetShown(count > 0)
        return offset+count
    end
    -- [STYLE] Attached grids touch the unit frame without screen-row padding or empty columns.
    local columns = self.attached and math.min(self.columns, math.max(count, 1)) or self.columns
    local width = self.attached and columns*(self.itemWidth+self.gapX)-self.gapX or self.width
    local padding = self.attached and 0 or self.rowSpacing/2+2
    local lines = math.max(1, math.ceil(count / columns))
    local height = lines*self.size + (lines-1)*self.gapY + padding*2
    if row.layoutCount ~= count then
        row.layoutCount = count
        row:SetSize(width, height)
        for i, icon in ipairs(row.icons) do
            local line, column = math.floor((i-1)/columns), (i-1)%columns
            local used = math.min(columns, math.max(0, count-line*columns))
            local spare = (columns-used)*(self.itemWidth+self.gapX)
            local x = self.align == "RIGHT" and spare or self.align == "CENTER" and spare/2 or 0
            if self.attached and self.attachSide == "LEFT" then column = used-1-column end
            x = x+column*(self.itemWidth+self.gapX)
            local y = self.grow == "UP" and lines-1-line or line
            icon:ClearAllPoints()
            icon:SetPoint("TOPLEFT", row, "TOPLEFT", x, -padding-y*(self.size+self.gapY))
        end
    end
    if self.attached then
        -- [12.0.1] Rebinding protected unit-frame anchors waits until combat ends.
        row:SetShown(MatchesUnit(row.anchor, row.unit) and row.guid ~= nil)
    else
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, -offset)
    end
    return offset + height
end

function Trace:Reset(hold)
    wipe(self.ledger)
    Sensor:Reset(hold)
    for _, row in ipairs(self.rows) do
        row.auras = {}
        self:ScanAuras(row, true)
    end
    self:UpdateCooldowns()
end

function Trace:OnEnable()
    if ns.db.profile.modules.SkillTracker == false then return end
    self:CreateFrame()
    self.running = true
    Sensor.engines[self] = true
    if not self.events then
        self.events = CreateFrame("Frame")
        self.events:SetScript("OnEvent", function(_, event, unit)
            if event == "PLAYER_SPECIALIZATION_CHANGED" then ns.SkillTracker:InvalidateSpec(unit) end
            if event == "ENCOUNTER_END" or event == "CHALLENGE_MODE_START" or event == "PLAYER_ENTERING_WORLD" then
                self:Reset(event == "CHALLENGE_MODE_START" and 2 or nil)
            end
            if event == "PLAYER_REGEN_DISABLED" then
                self:ExitEditPreview()
            elseif event == "PLAYER_REGEN_ENABLED" or event == "SPELLS_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
                self:ApplySettings()
            else self:RefreshRoster() end
        end)
        self.events:SetScript("OnUpdate", function(_, elapsed)
            self.elapsed = (self.elapsed or 0) + elapsed
            if self.elapsed < .2 then return end
            self.elapsed = 0
            if self.running then
                if self.attached and GetTime() >= (self.nextAnchorRefresh or 0) then
                    self.nextAnchorRefresh = GetTime() + 1
                    self:RefreshAnchors()
                end
                self:UpdateCooldowns()
                if (GetInspectSpecialization or (C_SpecializationInfo and C_SpecializationInfo.GetInspectSpecialization))
                    and GetTime() >= (self.nextSpecRefresh or 0) then
                    self.nextSpecRefresh = GetTime() + 2
                    self:RefreshRoster()
                end
            end
        end)
    end
    self.events:Show()
    for _, event in ipairs({"GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
        "PLAYER_REGEN_DISABLED", "SPELLS_CHANGED", "ENCOUNTER_END", "CHALLENGE_MODE_START", "ZONE_CHANGED_NEW_AREA", "SCENARIO_UPDATE",
        "INSPECT_READY", "PLAYER_SPECIALIZATION_CHANGED"}) do
        self.events:RegisterEvent(event)
    end
    for _, row in ipairs(self.rows) do
        row.observer:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", row.unit)
        row.observer:RegisterUnitEvent("UNIT_AURA", row.unit)
    end
    self:ApplySettings()
end

function Trace:OnDisable()
    self.running, self.preview = false, false
    Sensor.engines[self] = nil
    Sensor:Track(self, nil)
    if self.events then self.events:UnregisterAllEvents(); self.events:Hide() end
    for _, row in ipairs(self.rows or {}) do row.observer:UnregisterAllEvents() end
    if self.frame then self.frame:Hide() end
    if self.ledger then wipe(self.ledger) end
end

local function FillPreviewIcons(trace, row, class, spells)
    local db, fx, bars = trace.db, trace.fx or trace.db, trace.bars
    local omni = trace.barIndex and bars
    for i, icon in ipairs(row.icons) do
        local id = spells[i]
        icon:SetShown(id ~= nil)
        HideHidden(icon)
        if id then
            icon.texture:SetTexture(SpellTexture(id))
            SetLabel(icon, row, db, class, trace)
            icon.cooldown:Clear()
            icon.cooldown:SetHideCountdownNumbers(true)
            icon.count:SetText("")
            -- Sample states only: one active effect, a few cooldowns, the rest ready.
            local remaining = i == 1 and 42 or i % 4 == 3 and 6 + i * 3 or nil
            SetIconState(icon, true, remaining ~= nil, fx)
            if remaining then icon.cooldown:SetCooldown(GetTime() - (120 - remaining), 120) end
            local fraction
            if bars then
                if omni then icon.barCooldown:Clear() else icon.cooldown:SetDrawSwipe(false) end
                local value = remaining or 120
                if omni and db.reverseFill == false and remaining then value = 120 - remaining end
                icon.bar:SetMinMaxValues(0, 120)
                icon.bar:SetValue(value)
                fraction = value / 120
            end
            icon.text:SetText(fx.showNumbers ~= false and remaining and Clock(remaining) or "")
            trace:PaintBar(icon, class, remaining and "active" or "inactive", fraction)
            if icon.useGlow then icon.useGlow:SetShown(fx.useGlow == true and i == 2) end
        end
    end
    local id = spells[1]
    if not id then row.previewActive:Hide(); return end
    row.previewActive:SetParent(row.icons[1])
    row.previewActive:SetAllPoints(row.icons[1].texture)
    row.previewActive:SetFrameLevel(row.icons[1].cooldown:GetFrameLevel() + 10)
    row.previewActive.texture:SetTexture(SpellTexture(id))
    row.previewActive.cooldown:SetCooldown(GetTime() - 4, 12)
    row.previewActive.text:SetText("")
    ConfigureGlow(row.previewActive.glow, fx, false, not ns.SkillTracker:Glow(id))
    row.previewActive:Show()
end

function Trace:RenderPreview()
    Sensor:Track(self, nil)
    local classes = {}
    for _, class in ipairs({"PRIEST", "WARRIOR", "MAGE", "SHAMAN", "WARLOCK", "PALADIN", "HUNTER",
        "ROGUE", "DEATHKNIGHT", "MONK", "DRUID", "DEMONHUNTER", "EVOKER"}) do
        if #self:Spells(class) > 0 and #classes < #self.rows then classes[#classes+1] = class end
    end
    local offset = 0
    self.totalSlots, self.slots = 0, nil
    for _, class in ipairs(classes) do self.totalSlots = self.totalSlots + #self:Spells(class) end
    if self.barIndex and self.combined then self.width = self:GridWidth(self.totalSlots) end
    local recent = not self.barIndex and self.sortOrder ~= "spell"
    for index, row in ipairs(self.rows) do
        local class = index <= #TOKENS and classes[index]
        row:SetShown(class ~= nil)
        if class then
            local spells = {unpack(self:Spells(class))}
            if not recent then PriorityOrder(spells) end
            row.displayName = L["CT_CLASS_SHORT_" .. class]
            offset = self:LayoutRow(row, #spells, offset)
            if row.container then row.container:Hide() end
            FillPreviewIcons(self, row, class, spells)
        end
    end
    self:ResizeFrame(offset)
    self.frame:Show()
end

local CLASS_ORDER = {"WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT",
    "SHAMAN", "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER"}
local LIST_TOP, LIST_HEAD, LIST_ROW = 84, 30, 34
Trace.CLASS_ORDER = CLASS_ORDER

-- [STYLE] OmniCD Spells tab: type pills + clear/reset, class chips, then
-- spell | frame | priority | glow rows. Types stay DDingUI's defensives/cooldowns/cc.
function Trace:CreateSpellList(parent, groupFrame)
    local list = CreateFrame("Frame", nil, parent)
    local controls = ns.ToolkitControls or SL
    local G = ns.SkillTracker
    local radius = SL.Radius or {}
    local accent = SL.GetAccent and SL.GetAccent("MJToolkit") or C.text.highlight
    local maxRows = 0
    for _, class in ipairs(CLASS_ORDER) do
        maxRows = math.max(maxRows, #Data.cooldowns[class], #Data.defensives[class], #Data.cc[class])
    end
    list:SetHeight(LIST_TOP + LIST_HEAD + maxRows * LIST_ROW + 12)
    list.rows = {}
    local _, selected = UnitClass("player")
    if not Data.cooldowns[selected] then selected = "WARRIOR" end
    local category = Data.categories[1]
    local requested = {}
    local function Report(ok, reason)
        if reason then ns.PrintError(L[reason]) end
        return ok
    end
    local function MiniSlider(row, maximum, onChange)
        local slider = controls.CreateSlider(row, "MJToolkit", "", 0, maximum, 1, 0, {onChange=onChange})
        slider:SetSize(112, LIST_ROW)
        slider.label:Hide()
        slider.valueBox:SetSize(34, 22)
        slider.track:SetWidth(64)
        slider:SetFrameLevel(row:GetFrameLevel() + 2)
        return slider
    end
    local function PaintOverride(slider, override)
        local color = override and accent or C.border.default
        slider.valueBox:SetBackdropBorderColor(color[1], color[2], color[3], override and 1 or (color[4] or 1))
        slider.valueBox:SetTextColor(unpack(override and accent or C.text.highlight))
    end
    local function Populate()
        local spells = Data[category][selected]
        for index, row in ipairs(list.rows) do
            local id = spells[index]
            row.spellID = id
            row:SetShown(id ~= nil)
            if row.stripe then row.stripe:SetShown(id ~= nil) end
            if id then
                local info = C_Spell.GetSpellInfo(id)
                local on = G:IsSelected(id, selected) and (groupFrame == nil or G:Frame(id) == groupFrame)
                local frame, priority = G:Frame(id), G:Priority(id)
                row.icon:SetTexture(SpellTexture(id))
                row.icon:SetAlpha(on and 1 or .45)
                row.label:SetText(info and info.name or "…")
                row.label:SetTextColor(unpack(on and C.text.highlight or C.text.disabled))
                row.check:SetChecked(on, true)
                row.frame:SetValue(frame, true)
                row.priority:SetValue(priority, true)
                row.glow:SetChecked(G:Glow(id), true)
                for _, control in ipairs({row.frame, row.priority, row.glow}) do control:SetDisabledState(not on) end
                PaintOverride(row.frame, frame ~= G:TypeFrame(category))
                PaintOverride(row.priority, type(ns.db.profile.CooldownTrace.spellPriority[id]) == "number")
                if not info and not requested[id] then
                    requested[id] = true
                    C_Spell.RequestLoadSpellData(id)
                end
            end
        end
        list.sheet:SetHeight(LIST_HEAD + math.max(1, #spells) * LIST_ROW + 6)
    end
    list.Populate = Populate
    local categories = {}
    for _, id in ipairs(Data.categories) do
        categories[#categories+1] = {text=L["CT_CATEGORY_" .. id:upper()], value=id}
    end
    list.categoryPicker = controls.CreateSegmentedControl(list, "MJToolkit", "", categories,
        category, {width=300, height=30, onChange=function(value) category = value; Populate() end})
    list.categoryPicker:SetPoint("TOPLEFT")
    list.categoryPicker:SetWidth(300)
    list.categoryPicker.control:ClearAllPoints()
    list.categoryPicker.control:SetPoint("TOPLEFT", list.categoryPicker, "TOPLEFT", 0, 0)
    list.categoryPicker.control:SetPoint("TOPRIGHT", list.categoryPicker, "TOPRIGHT", 0, 0)
    local function Confirm(key, restore)
        local function Run() Report(G:ResetSpells(restore, groupFrame)); Populate() end
        if StaticPopupDialogs and StaticPopup_Show then
            StaticPopupDialogs.DDINGTOOLKIT_CT_SPELLS = {
                text=L[key], button1=ACCEPT or "OK", button2=CANCEL or "Cancel",
                OnAccept=Run, timeout=0, whileDead=true, hideOnEscape=true,
            }
            StaticPopup_Show("DDINGTOOLKIT_CT_SPELLS")
        else
            Run()
        end
    end
    list.resetSpells = controls.CreateButton(list, "MJToolkit", L["CT_RESET_SPELLS"],
        function() Confirm(groupFrame ~= nil and "CT_RESET_GROUP_SPELLS_CONFIRM" or "CT_RESET_SPELLS_CONFIRM", true) end, {width=100, height=30})
    list.resetSpells:SetPoint("TOPRIGHT")
    list.clearSpells = controls.CreateButton(list, "MJToolkit", L["CT_CLEAR_SPELLS"],
        function() Confirm(groupFrame ~= nil and "CT_CLEAR_GROUP_SPELLS_CONFIRM" or "CT_CLEAR_SPELLS_CONFIRM", false) end, {width=100, height=30})
    list.clearSpells:SetPoint("RIGHT", list.resetSpells, "LEFT", -8, 0)

    -- Class chips keep the old picker interface (GetValue/SetValue) for callers and tests.
    local chips = {}
    local picker = {}
    local function PaintChips()
        for _, chip in ipairs(chips) do
            local on = chip.class == selected
            local color = chip.color
            if on and color then
                chip:SetBackdropColor(color.r * .2 + .05, color.g * .2 + .05, color.b * .2 + .05, 1)
                chip:SetBackdropBorderColor(color.r, color.g, color.b, 1)
                chip.label:SetTextColor(color.r, color.g, color.b, 1)
            else
                chip:SetBackdropColor(unpack(on and C.bg.selected or C.bg.input))
                if on then chip:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1)
                else chip:SetBackdropBorderColor(unpack(C.border.default)) end
                chip.label:SetTextColor(unpack(on and C.text.highlight or C.text.normal))
            end
        end
    end
    function picker:GetValue() return selected end
    function picker:SetValue(class)
        if not Data.cooldowns[class] then return end
        selected = class
        PaintChips()
        Populate()
    end
    list.classPicker = picker
    for index, class in ipairs(CLASS_ORDER) do
        local chip = CreateFrame("Button", nil, list, "BackdropTemplate")
        chips[index] = chip
        chip.class = class
        chip:SetHeight(30)
        if controls.ApplyBackdrop then
            controls.ApplyBackdrop(chip, C.bg.input, C.border.default, radius.control)
        end
        chip.color = ClassColor(class)
        chip.bar = chip:CreateTexture(nil, "ARTWORK")
        chip.bar:SetSize(3, 12)
        chip.bar:SetPoint("LEFT", 6, 0)
        if chip.color then chip.bar:SetColorTexture(chip.color.r, chip.color.g, chip.color.b, 1) else chip.bar:Hide() end
        chip.label = Text(chip, 11, C.text.normal)
        chip.label:SetPoint("LEFT", chip.bar, "RIGHT", 4, 0)
        chip.label:SetPoint("RIGHT", -3, 0)
        chip.label:SetWordWrap(false)
        chip.label:SetText(rawget(L, "CT_CLASS_SHORT_" .. class) or (LOCALIZED_CLASS_NAMES_MALE or {})[class] or class)
        chip:SetScript("OnClick", function() picker:SetValue(class) end)
        chip:SetScript("OnEnter", function() chip.label:SetTextColor(unpack(C.text.highlight)) end)
        chip:SetScript("OnLeave", PaintChips)
    end

    list.sheet = CreateFrame("Frame", nil, list, "BackdropTemplate")
    list.sheet:SetPoint("TOPLEFT", 0, -LIST_TOP)
    list.sheet:SetPoint("TOPRIGHT", 0, -LIST_TOP)
    if controls.ApplyBackdrop then
        controls.ApplyBackdrop(list.sheet, C.bg.sidebar, C.border.default, radius.row)
    end
    local head = {}
    for key, text in pairs({spell="CT_COLUMN_SPELL", frame="CT_TAB_FRAME", priority="CT_TAB_PRIORITY", glow="CT_COLUMN_GLOW"}) do
        head[key] = Text(list.sheet, 11, C.text.dim)
        head[key]:SetText(L[text])
        head[key]:SetJustifyH(key == "spell" and "LEFT" or "CENTER")
    end
    list.header = head
    list.headLine = list.sheet:CreateTexture(nil, "ARTWORK")
    list.headLine:SetHeight(1)
    list.headLine:SetColorTexture(unpack(C.border.default))
    list.headLine:SetPoint("TOPLEFT", list.sheet, "TOPLEFT", 8, -LIST_HEAD + 4)
    list.headLine:SetPoint("TOPRIGHT", list.sheet, "TOPRIGHT", -8, -LIST_HEAD + 4)
    for index = 1, maxRows do
        local row = CreateFrame("Frame", nil, list)
        list.rows[index] = row
        row:SetHeight(LIST_ROW)
        row:SetFrameLevel(list.sheet:GetFrameLevel() + 2)
        local top = -LIST_TOP - LIST_HEAD - (index-1)*LIST_ROW
        row:SetPoint("TOPLEFT", list, "TOPLEFT", 6, top)
        row:SetPoint("TOPRIGHT", list, "TOPRIGHT", -6, top)
        if index % 2 == 0 then
            -- Drawn on the sheet so it always stays under the row's controls and text.
            row.stripe = list.sheet:CreateTexture(nil, "ARTWORK")
            row.stripe:SetAllPoints(row)
            local r, g, b = unpack(C.bg.hoverLight)
            row.stripe:SetColorTexture(r, g, b, .18)
        end
        row.check = controls.CreateCheckbox(row, "MJToolkit", "", false, {
            onChange=function(checked)
                Report(G:SetSpells(category, selected, row.spellID, checked, groupFrame))
                Populate()
            end,
        })
        row.check:SetSize(22, LIST_ROW)
        row.check:SetPoint("LEFT", row, "LEFT", 10, 0)
        row.check.box:ClearAllPoints()
        row.check.box:SetPoint("CENTER", row.check, "CENTER", 0, 0)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(24, 24)
        row.icon:SetPoint("LEFT", row, "LEFT", 40, 0)
        row.icon:SetTexCoord(.07, .93, .07, .93)
        row.label = Text(row, 13, C.text.highlight)
        row.label:SetPoint("LEFT", row.icon, "RIGHT", 10, 0)
        row.label:SetWordWrap(false)
        row.name = row.label
        row.glow = controls.CreateCheckbox(row, "MJToolkit", "", true, {
            onChange=function(checked) Report(G:SetSpellGlow(row.spellID, checked)); Populate() end,
        })
        row.glow:SetSize(22, LIST_ROW)
        row.glow:SetPoint("RIGHT", row, "RIGHT", -24, 0)
        row.glow.box:ClearAllPoints()
        row.glow.box:SetPoint("CENTER", row.glow, "CENTER", 0, 0)
        row.priority = MiniSlider(row, 100, function(value)
            Report(G:SetSpellPriority(row.spellID, value)); Populate()
        end)
        row.priority:SetPoint("RIGHT", row.glow, "LEFT", -34, 0)
        row.frame = MiniSlider(row, G.BAR_COUNT, function(value)
            if not Report(G:SetSpellFrame(row.spellID, value)) then row.frame:SetValue(G:Frame(row.spellID), true) end
            Populate()
        end)
        row.frame:SetPoint("RIGHT", row.priority, "LEFT", -26, 0)
        row.frame:SetShown(groupFrame == nil)
        row.label:SetPoint("RIGHT", groupFrame == nil and row.frame or row.priority, "LEFT", -12, 0)
        local hover = CreateFrame("Frame", nil, row)
        hover:SetPoint("TOPLEFT", row.icon, "TOPLEFT")
        hover:SetPoint("BOTTOMRIGHT", row.label, "BOTTOMRIGHT")
        hover:EnableMouse(true)
        hover:SetScript("OnEnter", function()
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(row.spellID)
            GameTooltip:Show()
        end)
        hover:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    local function Layout(_, width)
        width = width or list:GetWidth() or 0
        if width < 100 then return end
        list.categoryPicker:SetWidth(math.max(1, math.min(300, width - 220)))
        local gap = 4
        local chipWidth = math.floor((width - gap * (#chips - 1)) / #chips)
        for index, chip in ipairs(chips) do
            chip:ClearAllPoints()
            chip:SetPoint("TOPLEFT", list, "TOPLEFT", (index - 1) * (chipWidth + gap), -40)
            chip:SetWidth(index == #chips and width - (index - 1) * (chipWidth + gap) or chipWidth)
        end
        local row = list.rows[1]
        if row then
            head.spell:ClearAllPoints()
            head.spell:SetPoint("LEFT", list.sheet, "TOPLEFT", 6 + 74, -LIST_HEAD / 2 + 2)
            for _, key in ipairs({"frame", "priority", "glow"}) do
                local control = row[key]
                head[key]:ClearAllPoints()
                head[key]:SetPoint("CENTER", control, "CENTER", 0, 0)
                head[key]:SetPoint("TOP", list.sheet, "TOP", 0, -8)
            end
        end
    end
    head.frame:SetShown(groupFrame == nil)
    list:SetScript("OnEvent", function(_, _, id, success)
        if success and requested[id] then Populate() end
    end)
    list:SetScript("OnShow", function(frame) frame:RegisterEvent("SPELL_DATA_LOAD_RESULT"); Populate() end)
    list:SetScript("OnHide", function(frame) frame:UnregisterAllEvents(); GameTooltip:Hide() end)
    list:SetScript("OnSizeChanged", Layout)
    list:RegisterEvent("SPELL_DATA_LOAD_RESULT")
    Layout(list, list:GetWidth())
    PaintChips()
    Populate()
    return list
end

function Trace:EnterEditPreview()
    self:CreateFrame()
    if Restricted() then return end
    self.preview = true
    self:ApplySettings()
end

function Trace:ExitEditPreview()
    if not self.frame then return end
    self.preview = false
    for _, row in ipairs(self.rows) do
        row.previewActive:Hide()
        if row.container then row.container:Show() end
    end
    local party = self.barIndex and self.db.unitBar == true or not self.barIndex and self.db.attachTo == "party"
    if InCombatLockdown() and party and not self.attached then
        self.suspended = true
    end
    self:ApplySettings()
    if InCombatLockdown() then self:RefreshRoster() end
end
