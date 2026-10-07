-- DDingUI Toolkit - shared ready-check visuals -- [STYLE]
-- One look for "공격대 전투 준비" (RaidPreparation, 32px icons) and "준비 상태 점검"
-- (ReadyCheckAssistant, 24px icons): status colours, icon cell with a 1px status border and a
-- 16px round count badge, status pills, the series "X" close button and small text buttons.
-- Colours come from StyleLib Colors (status.success / warning / error, text, bg); the fallback
-- values below are only used when the embedded StyleLib is missing.

local _, ns = ...

local RS = {}
ns.ReadyStatus = RS

RS.RAID_ICON = 32
RS.PERSONAL_ICON = 24
RS.BADGE = 16

-- [STYLE] Toolkit's own item icons (64x64 TGA, painted in the in-game icon style, no built-in border).
local ICON_PATH = "Interface\\AddOns\\DDingUI_Toolkit\\Media\\ReadyStatus\\ready_"
RS.ITEM_ICONS = {
    food = ICON_PATH .. "food",
    flask = ICON_PATH .. "flask",
    rune = ICON_PATH .. "rune",
    raidBuff = ICON_PATH .. "raidbuff",
    weapon = ICON_PATH .. "weapon",
    durability = ICON_PATH .. "durability",
}

local function IsOwnIcon(texture)
    return type(texture) == "string" and texture:find(ICON_PATH, 1, true) == 1
end
RS.IsOwnIcon = IsOwnIcon

local FALLBACK = {
    status = {
        success = { 0.30, 0.80, 0.30, 1 },
        warning = { 0.90, 0.75, 0.20, 1 },
        error = { 0.90, 0.25, 0.25, 1 },
    },
    text = {
        normal = { 0.85, 0.85, 0.85, 1 }, highlight = { 1, 1, 1, 1 },
        dim = { 0.66, 0.66, 0.66, 1 }, disabled = { 0.50, 0.50, 0.50, 1 },
    },
    bg = { main = { 0.10, 0.10, 0.10, 0.95 }, input = { 0.06, 0.06, 0.06, 0.80 } },
    border = { default = { 0.25, 0.25, 0.25, 0.50 } },
}

local function Lib() return _G.DDingUI_StyleLib end

local function Token(group, key)
    local lib = Lib()
    local colors = lib and lib.Colors
    local value = colors and colors[group] and colors[group][key]
    return value or FALLBACK[group][key]
end
RS.Token = Token

local STATE_TOKEN = { ok = "success", warn = "warning", bad = "error" }

--- ok / warn / bad -> StyleLib status colour, anything else -> dim text colour.
function RS.Color(state)
    local key = STATE_TOKEN[state]
    if key then return Token("status", key) end
    return Token("text", "dim")
end

function RS.Font()
    local lib = Lib()
    return (lib and lib.Font and lib.Font.path) or "Fonts\\2002.TTF"
end

local function Unpack(color, alpha)
    return color[1], color[2], color[3], alpha or color[4] or 1
end
RS.Unpack = Unpack

--- r, g, b only (GameTooltip:AddLine's 5th argument is "wrap", not alpha).
function RS.RGB(color)
    return color[1], color[2], color[3]
end

local function Radius(key, fallback)
    local lib = Lib()
    return (lib and lib.Radius and lib.Radius[key]) or fallback
end
RS.Radius = Radius

--- Rounded surface (StyleLib MakeRounded), plain backdrop when the library is missing.
function RS.Round(frame, radius, background, border)
    local lib = Lib()
    if lib and lib.MakeRounded then
        lib.MakeRounded(frame, radius, background, border)
    elseif frame.SetBackdrop then
        frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        frame:SetBackdropColor(Unpack(background))
        frame:SetBackdropBorderColor(Unpack(border))
    end
end

--- Rounded fill texture; tinted with RS.Tint.
function RS.RoundFill(texture, radius)
    local lib = Lib()
    if lib and lib.RoundTexture then lib.RoundTexture(texture, radius) end
    return texture
end

function RS.Tint(texture, color, alpha)
    local r, g, b, a = Unpack(color, alpha)
    if texture._ddslRoundTex then
        texture:SetVertexColor(r, g, b, a)
    else
        texture:SetColorTexture(r, g, b, a)
    end
end

function RS.Text(parent, size, color, text)
    local label = parent:CreateFontString(nil, "OVERLAY")
    label:SetFont(RS.Font(), math.max(12, size or 12), "")
    label:SetTextColor(Unpack(color or Token("text", "normal")))
    label:SetShadowOffset(1, -1)
    label:SetShadowColor(0, 0, 0, 0.6)
    label:SetJustifyH("LEFT")
    label:SetJustifyV("MIDDLE")
    label:SetWordWrap(false)
    label:SetText(text or "")
    return label
end

--- Icon cell: game icon + 1px status border + optional round count badge (top right, 16px).
--- cell:SetIcon(texture), cell:SetState("ok"|"warn"|"bad"|nil), cell:SetBadge(count, state),
--- cell:SetRound(true) for a circular spec icon (no square border).
function RS.CreateIcon(parent, size)
    local cell = CreateFrame("Frame", nil, parent)
    cell:SetSize(size, size)
    cell.size = size

    cell.icon = cell:CreateTexture(nil, "ARTWORK")
    cell.icon:SetPoint("TOPLEFT", 1, -1)
    cell.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    cell.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    cell.edges = {}
    for index = 1, 4 do
        local edge = cell:CreateTexture(nil, "OVERLAY")
        cell.edges[index] = edge
    end
    cell.edges[1]:SetPoint("TOPLEFT"); cell.edges[1]:SetPoint("TOPRIGHT"); cell.edges[1]:SetHeight(1)
    cell.edges[2]:SetPoint("BOTTOMLEFT"); cell.edges[2]:SetPoint("BOTTOMRIGHT"); cell.edges[2]:SetHeight(1)
    cell.edges[3]:SetPoint("TOPLEFT"); cell.edges[3]:SetPoint("BOTTOMLEFT"); cell.edges[3]:SetWidth(1)
    cell.edges[4]:SetPoint("TOPRIGHT"); cell.edges[4]:SetPoint("BOTTOMRIGHT"); cell.edges[4]:SetWidth(1)

    local badge = CreateFrame("Frame", nil, cell)
    badge:SetSize(RS.BADGE, RS.BADGE)
    badge:SetPoint("CENTER", cell, "TOPRIGHT", -2, -2)
    badge:SetFrameLevel((cell:GetFrameLevel() or 1) + 3)
    badge.fill = RS.RoundFill(badge:CreateTexture(nil, "ARTWORK"), Radius("row", 8))
    badge.fill:SetAllPoints()
    badge.text = RS.Text(badge, 12, Token("text", "highlight"), "")
    badge.text:SetPoint("CENTER", 0, 0)
    badge.text:SetJustifyH("CENTER")
    badge:Hide()
    cell.badge = badge

    function cell:SetIcon(texture)
        self.icon:SetTexture(texture or 134400)
        -- game icons carry a baked border, so crop 8%; our own icons are full-bleed
        if not self.round then
            if IsOwnIcon(texture) then
                self.icon:SetTexCoord(0, 1, 0, 1)
            else
                self.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
        end
    end

    function cell:SetRound(round)
        self.round = round and true or false
        if self.round and self.icon.SetMask then
            self.icon:SetTexCoord(0, 1, 0, 1)
            self.icon:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        end
        self:SetState(self.state)
    end

    function cell:SetState(state)
        self.state = state
        local color = state and RS.Color(state) or Token("border", "default")
        for _, edge in ipairs(self.edges) do
            edge:SetColorTexture(Unpack(color))
            edge:SetShown(not self.round)
        end
    end

    function cell:SetBadge(count, state)
        count = tonumber(count) or 0
        self.badgeCount = count
        self.badgeState = count > 0 and state or nil
        if count <= 0 then self.badge:Hide(); return end
        RS.Tint(self.badge.fill, RS.Color(state))
        -- white on red, dark on yellow for contrast
        self.badge.text:SetTextColor(Unpack(state == "warn" and Token("bg", "main") or Token("text", "highlight"), 1))
        self.badge.text:SetText(count > 99 and "99" or tostring(count))
        self.badge:SetWidth(math.max(RS.BADGE, (self.badge.text:GetStringWidth() or 0) + 8))
        self.badge:Show()
    end

    cell:SetState(nil)
    return cell
end

--- Status pill (radius 8): pill:SetPill(text, state) -> tinted background (14%) + state text.
function RS.CreatePill(parent)
    local pill = CreateFrame("Frame", nil, parent)
    pill:SetHeight(20)
    pill.fill = RS.RoundFill(pill:CreateTexture(nil, "BACKGROUND"), Radius("row", 8))
    pill.fill:SetAllPoints()
    pill.text = RS.Text(pill, 12, Token("text", "dim"), "")
    pill.text:SetPoint("CENTER", 0, 0)
    pill.text:SetJustifyH("CENTER")
    function pill:SetPill(text, state)
        self.state = state
        self.text:SetText(text or "")
        local color = RS.Color(state)
        self.text:SetTextColor(Unpack(color))
        if state == "ok" or state == "warn" or state == "bad" then
            RS.Tint(self.fill, color, 0.14)
        else
            RS.Tint(self.fill, Token("bg", "input"))
        end
        self:SetWidth(math.max(20, (self.text:GetStringWidth() or 0) + 16))
    end
    return pill
end

--- Series close button: the StyleLib title-bar "X" glyph, 18x18, dim -> error on hover.
function RS.CreateCloseButton(parent, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(18, 18)
    button.label = RS.Text(button, 12, Token("text", "dim"), "X")
    button.label:SetPoint("CENTER", 0, 0)
    button.label:SetJustifyH("CENTER")
    button:SetScript("OnEnter", function(self) self.label:SetTextColor(Unpack(RS.Color("bad"))) end)
    button:SetScript("OnLeave", function(self) self.label:SetTextColor(Unpack(Token("text", "dim"))) end)
    button:SetScript("OnClick", onClick)
    return button
end

--- Small rounded text button (height 20, control radius 6), width follows the label.
function RS.CreateTextButton(parent, label, onClick)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetHeight(20)
    if button.RegisterForClicks then button:RegisterForClicks("LeftButtonUp") end
    RS.Round(button, Radius("control", 6), Token("bg", "input"), Token("border", "default"))
    button.label = RS.Text(button, 12, Token("text", "normal"), label)
    button.label:SetPoint("CENTER", 0, 0)
    button.label:SetJustifyH("CENTER")
    button:SetWidth(math.max(32, (button.label:GetStringWidth() or 0) + 14))
    button:SetScript("OnEnter", function(self)
        if self.disabled then return end
        self.label:SetTextColor(Unpack(Token("text", "highlight")))
    end)
    button:SetScript("OnLeave", function(self)
        self.label:SetTextColor(Unpack(Token("text", self.disabled and "disabled" or "normal")))
    end)
    button:SetScript("OnClick", function(self, ...)
        if self.disabled then return end
        if onClick then onClick(self, ...) end
    end)
    function button:SetDisabledState(disabled)
        self.disabled = disabled and true or false
        self.label:SetTextColor(Unpack(Token("text", self.disabled and "disabled" or "normal")))
        self:SetAlpha(self.disabled and 0.6 or 1)
    end
    return button
end

--- Tooltip helper: class-coloured name.
function RS.ClassColor(classToken)
    local color = type(classToken) == "string" and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
    if color then return color.r or 1, color.g or 1, color.b or 1 end
    local normal = Token("text", "normal")
    return normal[1], normal[2], normal[3]
end
