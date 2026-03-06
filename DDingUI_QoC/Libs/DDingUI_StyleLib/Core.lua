------------------------------------------------------
-- DDingUI_StyleLib :: Core
-- Namespace, accent preset registration, addon registry
------------------------------------------------------
local MAJOR, MINOR = "DDingUI-StyleLib-1.0", 1
local lib, oldMinor = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

-- 하위 호환: 글로벌 참조 유지
DDingUI_StyleLib = lib

local Lib = lib

Lib.version = MINOR

------------------------------------------------------
-- Accent Presets
------------------------------------------------------
Lib.AccentPresets = {
    ["UnitFrames"] = {
        from  = { 0.30, 0.85, 0.45, 1.0 },  -- #4dd973 bright green
        to    = { 0.12, 0.55, 0.20, 1.0 },  -- #1f8c33 dark green (gradient end)
        light = { 0.45, 0.92, 0.55, 1.0 },  -- #73eb8c hover / light variant
        dark  = { 0.08, 0.42, 0.15, 1.0 },  -- #146b26 pressed / dark variant
    },
    ["CDM"] = {
        from  = { 0.90, 0.45, 0.12, 1.0 },  -- bright orange (CLAUDE.md spec)
        to    = { 0.60, 0.18, 0.05, 1.0 },  -- dark orange (gradient end)
        light = { 1.00, 0.60, 0.25, 1.0 },  -- hover / light variant
        dark  = { 0.50, 0.15, 0.04, 1.0 },  -- pressed / dark variant
    },
    ["MJToolkit"] = {
        from  = { 0.20, 0.75, 0.90, 1.0 },  -- bright cyan
        to    = { 0.08, 0.40, 0.65, 1.0 },  -- dark cyan
        light = { 0.40, 0.85, 0.95, 1.0 },  -- light variant
        dark  = { 0.10, 0.55, 0.75, 1.0 },  -- dark variant
    },
    ["Profile"] = { -- [STYLE] 빨간색
        from  = { 1.00, 0.27, 0.27, 1.0 },  -- #ff4444 bright red
        to    = { 0.70, 0.10, 0.10, 1.0 },  -- #b31a1a dark red (gradient end)
        light = { 1.00, 0.50, 0.50, 1.0 },  -- #ff8080 hover / light variant
        dark  = { 0.55, 0.08, 0.08, 1.0 },  -- #8c1414 pressed / dark variant
    },
    ["Essential"] = { -- [ESSENTIAL-DESIGN]
        from  = { 1.00, 0.82, 0.20, 1.0 },  -- #ffd133 bright yellow
        to    = { 0.80, 0.60, 0.10, 1.0 },  -- #cc991a dark yellow (gradient end)
        light = { 1.00, 0.90, 0.45, 1.0 },  -- #ffe673 hover / light variant
        dark  = { 0.65, 0.48, 0.08, 1.0 },  -- #a67a14 pressed / dark variant
    },
    ["Nameplate"] = { -- [STYLE]
        from  = { 0.65, 0.35, 0.85, 1.0 },  -- #a659d9 bright purple
        to    = { 0.35, 0.15, 0.55, 1.0 },  -- #59268c dark purple (gradient end)
        light = { 0.80, 0.55, 0.95, 1.0 },  -- #cc8cf2 hover / light variant
        dark  = { 0.25, 0.10, 0.40, 1.0 },  -- #401a66 pressed / dark variant
    },
    ["Controller"] = { -- [STYLE]
        from  = { 0.60, 0.60, 0.60, 1.0 },  -- #999999 neutral grey
        to    = { 0.40, 0.40, 0.40, 1.0 },  -- #666666 dark grey
        light = { 0.75, 0.75, 0.75, 1.0 },  -- #bfbfbf light grey
        dark  = { 0.30, 0.30, 0.30, 1.0 },  -- #4d4d4d pressed grey
    },
    ["QoC"] = { -- [STYLE] 보라-빨강
        from  = { 0.85, 0.20, 0.50, 1.0 },  -- #d93380 bright purple-red
        to    = { 0.55, 0.10, 0.30, 1.0 },  -- #8c1a4d dark purple-red
        light = { 0.95, 0.40, 0.65, 1.0 },  -- #f266a6 hover
        dark  = { 0.40, 0.05, 0.20, 1.0 },  -- #660d33 pressed
    },
}

-- Fallback accent (neutral grey gradient)
local FALLBACK_ACCENT = {
    from = { 0.60, 0.60, 0.60, 1.0 },
    to   = { 0.35, 0.35, 0.35, 1.0 },
}

------------------------------------------------------
-- Addon Registry
------------------------------------------------------
local registeredAddons = {}

--- Register an addon with the style library.
--- @param addonName string  Unique addon identifier
--- @param accentPreset table|nil  { from = {r,g,b,a}, to = {r,g,b,a} }  Optional custom accent; if nil, looks up AccentPresets[addonName]
function Lib.RegisterAddon(addonName, accentPreset)
    if accentPreset then
        Lib.AccentPresets[addonName] = accentPreset
    end
    registeredAddons[addonName] = true
end

--- Get accent colours for an addon.
--- @param addonName string
--- @return table from   {r,g,b,a}  primary accent
--- @return table to     {r,g,b,a}  gradient end
--- @return table light  {r,g,b,a}  hover / light variant
--- @return table dark   {r,g,b,a}  pressed / dark variant
function Lib.GetAccent(addonName)
    local preset = Lib.AccentPresets[addonName] or FALLBACK_ACCENT
    return preset.from, preset.to, preset.light or preset.from, preset.dark or preset.to
end

--- Check if an addon has been registered.
--- @param addonName string
--- @return boolean
function Lib.IsRegistered(addonName)
    return registeredAddons[addonName] == true
end

------------------------------------------------------
-- Shared Textures  -- [12.0.1]
------------------------------------------------------
Lib.Textures = {
    flat = [[Interface\Buttons\WHITE8x8]],  -- single source for all addons
}

------------------------------------------------------
-- CallbackHandler (Controller 연동)  -- [CONTROLLER]
------------------------------------------------------
local CBH = LibStub("CallbackHandler-1.0", true)
if CBH then
    Lib.callbacks = Lib.callbacks or CBH:New(Lib)
end

--- Fire a callback event to all registered listeners.
--- @param event string  e.g. "MediaChanged"
--- @param ...   any     additional arguments
function Lib:Fire(event, ...)
    if self.callbacks then
        self.callbacks:Fire(event, ...)
    end
end

------------------------------------------------------
-- Dynamic Font/Texture API  -- [CONTROLLER]
------------------------------------------------------

--- Get the current primary or secondary font path.
--- Controller가 설치되어 있으면 Controller가 설정한 값 반환.
--- @param category string  "primary" | "secondary"
--- @return string  font file path
function Lib:GetFont(category)
    if category == "secondary" then
        return self.Font.default or "Fonts\\FRIZQT__.TTF"
    end
    return self.Font.path or "Fonts\\2002.TTF"
end

--- Get scaled font size.
--- @param category string  "title" | "section" | "normal" | "small"
--- @return number  scaled font size
function Lib:GetFontSize(category)
    local base = self.Font[category] or self.Font.normal or 13
    local scale = self.Font.sizeScale or 1.0
    return math.floor(base * scale + 0.5)
end

--- Get texture path by key.
--- @param key string  "flat" | "statusBar"
--- @return string  texture path
function Lib:GetTexture(key)
    return self.Textures[key] or self.Textures.flat or [[Interface\Buttons\WHITE8x8]]
end
