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
    ["Profile"] = { -- [12.0.1]
        from  = { 0.00, 0.80, 1.00, 1.0 },  -- #00ccff DDingUI cyan
        to    = { 0.00, 0.50, 0.80, 1.0 },  -- dark cyan (gradient end)
        light = { 0.30, 0.90, 1.00, 1.0 },  -- hover / light variant
        dark  = { 0.00, 0.40, 0.65, 1.0 },  -- pressed / dark variant
    },
    ["Essential"] = { -- [ESSENTIAL-DESIGN]
        from  = { 1.00, 0.82, 0.20, 1.0 },  -- #ffd133 bright yellow
        to    = { 0.80, 0.60, 0.10, 1.0 },  -- #cc991a dark yellow (gradient end)
        light = { 1.00, 0.90, 0.45, 1.0 },  -- #ffe673 hover / light variant
        dark  = { 0.65, 0.48, 0.08, 1.0 },  -- #a67a14 pressed / dark variant
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
