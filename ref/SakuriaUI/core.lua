SakuriaUI = {}
local f = CreateFrame("Frame")

local pending = {}
local worldReady = false

-- Notice to myself; needs bump to reset users settings and show reset message
local DB_VERSION = 1

local DEFAULTS = {
    fadeActionBars     = false,
    fadeStanceBar      = false,
    fadePetBar         = false,

    cleanIcons         = true,
    iconFlower         = true,

    hideMenuBar        = false,
    hideBagBar         = false,

    crosshair          = false,
    disableAuraOverlay = false,
    bossMute           = false,

    bossMuteSettings = {
        disableSfx         = true,
        disableMusic       = true,
        disableAmbience    = false,
        disableErrorSpeech = true,
    },

    fadeBars = {
        MainActionBar         = false,
        MultiBarBottomLeft    = false,
        MultiBarBottomRight   = false,
        MultiBarRight         = false,
        MultiBarLeft          = false,
        MultiBar5             = false,
        MultiBar6             = false,
        MultiBar7             = false,
    },
}

local function ApplyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            ApplyDefaults(dst[k], v)
        else
            if dst[k] == nil then dst[k] = v end
        end
    end
end

function SakuriaUI:GetDB()
    SakuriaUI_DB = SakuriaUI_DB or {}

    local savedVersion = tonumber(SakuriaUI_DB.__version) or 0
    if savedVersion ~= DB_VERSION then
        SakuriaUI_DB = {
            __version = DB_VERSION,
            __showResetMessage = true,
        }
    end

    ApplyDefaults(SakuriaUI_DB, DEFAULTS)
    SakuriaUI_DB.__version = DB_VERSION

    return SakuriaUI_DB
end

function SakuriaUI:IsReady()
    return worldReady
end

function SakuriaUI:Schedule(func)
    if worldReady then
        func()
    else
        pending[#pending + 1] = func
    end
end

function SakuriaUI:Init()
    self:GetDB()

    self.Modules = {
        fadeActionBars = {
            Enable  = SakuriaUI_EnableFadeActionBars,
            Disable = SakuriaUI_DisableFadeActionBars,
        },
        fadeStanceBar = {
            Enable  = SakuriaUI_EnableFadeStanceBar,
            Disable = SakuriaUI_DisableFadeStanceBar,
        },
        fadePetBar = {
            Enable  = SakuriaUI_EnableFadePetBar,
            Disable = SakuriaUI_DisableFadePetBar,
        },
        cleanIcons = {
            Enable  = SakuriaUI_EnableCleanIcons,
            Disable = SakuriaUI_DisableCleanIcons,
        },
        hideMenuBar = {
            Enable  = SakuriaUI_HideMenu and SakuriaUI_HideMenu.Enable,
            Disable = SakuriaUI_HideMenu and SakuriaUI_HideMenu.Disable,
        },
        hideBagBar = {
            Enable  = SakuriaUI_HideBags and SakuriaUI_HideBags.Enable,
            Disable = SakuriaUI_HideBags and SakuriaUI_HideBags.Disable,
        },
        crosshair = {
            Enable  = SakuriaUI_Crosshair and SakuriaUI_Crosshair.Enable,
            Disable = SakuriaUI_Crosshair and SakuriaUI_Crosshair.Disable,
        },
        disableAuraOverlay = {
            Enable  = SakuriaUI_DisableAuraOverlay and SakuriaUI_DisableAuraOverlay.Enable,
            Disable = SakuriaUI_DisableAuraOverlay and SakuriaUI_DisableAuraOverlay.Disable,
        },
        bossMute = {
            Enable  = SakuriaUI_BossMute and SakuriaUI_BossMute.Enable,
            Disable = SakuriaUI_BossMute and SakuriaUI_BossMute.Disable,
        },
    }
end

function SakuriaUI:ApplyModule(key)
    local db = self:GetDB()
    local mod = self.Modules and self.Modules[key]
    if not mod then return end

    local enabled = db[key]
    if enabled then
        if mod.Enable then mod.Enable() end
    else
        if mod.Disable then mod.Disable() end
    end
end

function SakuriaUI:ApplyAllModules()
    self:GetDB()

    for key in pairs(self.Modules or {}) do
        if key ~= "cleanIcons" then
            self:ApplyModule(key)
        end
    end

    local clean = self.Modules and self.Modules.cleanIcons
    if clean and clean.Enable then
        clean.Enable()
    end

    if SakuriaUI_Bindings and SakuriaUI_Bindings.Enable then
        SakuriaUI_Bindings.Enable()
    end
end

local startup = CreateFrame("Frame")
startup:RegisterEvent("ADDON_LOADED")
startup:SetScript("OnEvent", function(_, _, addon)
    if addon == "SakuriaUI" then
        SakuriaUI:Init()
    end
end)

f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function()
    worldReady = true

    for i = 1, #pending do
        pending[i]()
    end
    pending = {}

    if SakuriaUI.Modules then
        SakuriaUI:ApplyAllModules()
    end
end)

SLASH_SAKURIAUI1 = "/sui"
SLASH_SAKURIAUI2 = "/sakuria"
SlashCmdList["SAKURIAUI"] = function()
    local cfg = _G.SakuriaUIConfig
    if not cfg then return end

    if cfg:IsShown() then
        cfg:Hide()
    else
        cfg:Show()
    end
end

-- Reset SavedVariables and reload
SLASH_SAKURIAUIRESET1 = "/suireset"
SlashCmdList["SAKURIAUIRESET"] = function()
    if InCombatLockdown() then
        print("|cffffffffSakuria|r|cffff7abfUI|r: Can't reset in combat!")
        return
    end

    -- Fresh DB
    SakuriaUI_DB = {
        __version = DB_VERSION,
        __showResetMessage = true,
        __lastSeenUpdatePopup = 0,
    }

    ApplyDefaults(SakuriaUI_DB, DEFAULTS)
    SakuriaUI_DB.__version = DB_VERSION

    print("|cffffffffSakuria|r|cffff7abfUI|r: Settings reset to defaults. Reloading...")
    ReloadUI()
end

do
    local loginMsgFrame = CreateFrame("Frame")
    loginMsgFrame:RegisterEvent("PLAYER_LOGIN")
    loginMsgFrame:SetScript("OnEvent", function()
        SakuriaUI:GetDB()
		
        print("|cffffffffSakuria|r|cffff7abfUI|r: Type |cffff7abf/sui|r or |cffff7abf/sakuria|r to open the config!")

        -- Reset notice (only show once per update)
        if SakuriaUI_DB.__showResetMessage then
            print("|cffffffffSakuria|r|cffff7abfUI|r: Your settings were reset due to an update (DB v" .. DB_VERSION .. ")")
            SakuriaUI_DB.__showResetMessage = nil
        end
		
        if SakuriaUI_OnUpdate and SakuriaUI_OnUpdate.MaybeShow then
            SakuriaUI_OnUpdate.MaybeShow()
        end
    end)
end