--[[
    DDingUI Classic Skin
    Core.lua — 플러그인 초기화, 토글, SavedVariables

    비파괴적 PostHook 패턴:
    - CDM 스킨 적용 완료 후 블리자드 기본 UI 스타일로 오버라이드
    - 플러그인 비활성화 시 CDM 원본 스타일 유지
]]

local ADDON_NAME, ns = ...

-----------------------------------------------
-- Saved Variables defaults
-----------------------------------------------

local DEFAULTS = {
    enabled = true,
    skinIcons = true,
    skinBars = true,
    skinCastBar = true,

    -- Icon options
    iconBorderStyle = "classic",      -- "classic" = UI-Quickslot2, "simple" = thin line
    iconBorderInset = 8,              -- 보더 아이콘 밖 확장 크기

    -- Bar options
    barTexture = "blizzard",          -- "blizzard" = UI-StatusBar, "flat" = WHITE8X8
}

-----------------------------------------------
-- Core namespace
-----------------------------------------------

local ClassicSkin = {}
ns.ClassicSkin = ClassicSkin
ClassicSkin.enabled = true

-- Weak table for per-icon classic skin data (prevents memory leaks)
local skinData = setmetatable({}, { __mode = "k" })

-- Get or create skin data for a frame
function ClassicSkin:GetData(frame)
    local d = skinData[frame]
    if not d then
        d = {}
        skinData[frame] = d
    end
    return d
end

-----------------------------------------------
-- Initialization
-----------------------------------------------

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == ADDON_NAME then
        -- Initialize SavedVariables
        DDingUI_Skin_ClassicDB = DDingUI_Skin_ClassicDB or {}
        for k, v in pairs(DEFAULTS) do
            if DDingUI_Skin_ClassicDB[k] == nil then
                DDingUI_Skin_ClassicDB[k] = v
            end
        end

        ns.db = DDingUI_Skin_ClassicDB
        ClassicSkin.enabled = ns.db.enabled

        -- Wait for DDingUI to fully load, then install hooks
        C_Timer.After(0.1, function()
            ClassicSkin:InstallHooks()
        end)

        self:UnregisterEvent("ADDON_LOADED")
    end
end)

-----------------------------------------------
-- Hook Installation
-----------------------------------------------

function ClassicSkin:InstallHooks()
    -- DDingUI는 AceAddon-3.0으로 생성됨 (Main.lua: LibStub("AceAddon-3.0"):NewAddon("DDingUI", ...))
    local DDingUI
    pcall(function()
        DDingUI = LibStub("AceAddon-3.0"):GetAddon("DDingUI")
    end)

    if not DDingUI then
        -- Retry after more loading time
        C_Timer.After(1.0, function()
            self:InstallHooks()
        end)
        return
    end

    -- Find IconViewers module
    local IconViewers = DDingUI.IconViewers

    if not IconViewers then
        -- Retry after more loading time
        C_Timer.After(1.0, function()
            self:InstallHooks()
        end)
        return
    end

    ns.DDingUI = DDingUI
    ns.IconViewers = IconViewers

    -- ========================================
    -- HOOK 1: SkinIcon PostHook
    -- CDM이 아이콘 스킨을 적용한 직후 블리자드 스타일로 오버라이드
    -- ========================================
    if IconViewers.SkinIcon then
        hooksecurefunc(IconViewers, "SkinIcon", function(self2, icon, settings)
            if not ClassicSkin.enabled or not ns.db.skinIcons then return end

            local ok, err = pcall(ns.SkinIcons.PostSkinIcon, ns.SkinIcons, icon, settings)
            if not ok then
                -- Silent fail: 에러가 CDM 기능에 영향을 주면 안됨
            end
        end)
        ns.Debug("SkinIcon PostHook installed")
    end

    -- ========================================
    -- HOOK 2: GetPowerBar PostHook (바 생성 후)
    -- ========================================
    local ResourceBars = DDingUI.ResourceBars
    if ResourceBars and ResourceBars.UpdatePowerBar then
        hooksecurefunc(ResourceBars, "UpdatePowerBar", function()
            if not ClassicSkin.enabled or not ns.db.skinBars then return end

            local bar = DDingUI.powerBar
            if bar then
                pcall(ns.SkinBars.PostSkinPowerBar, ns.SkinBars, bar)
            end
        end)
        ns.Debug("PowerBar PostHook installed")
    end

    if ResourceBars and ResourceBars.UpdateSecondaryPowerBar then
        hooksecurefunc(ResourceBars, "UpdateSecondaryPowerBar", function()
            if not ClassicSkin.enabled or not ns.db.skinBars then return end

            local bar = DDingUI.secondaryPowerBar
            if bar then
                pcall(ns.SkinBars.PostSkinSecondaryBar, ns.SkinBars, bar)
            end
        end)
        ns.Debug("SecondaryPowerBar PostHook installed")
    end

    -- ========================================
    -- HOOK 3: BuffTrackerBar PostHook
    -- ========================================
    if ResourceBars and ResourceBars.UpdateBuffTrackerBar then
        hooksecurefunc(ResourceBars, "UpdateBuffTrackerBar", function()
            if not ClassicSkin.enabled or not ns.db.skinBars then return end

            local bar = DDingUI.buffTrackerBar
            if bar then
                pcall(ns.SkinBars.PostSkinBuffTrackerBar, ns.SkinBars, bar)
            end
        end)
        ns.Debug("BuffTrackerBar PostHook installed")
    end

    ns.Debug("|cff00ff00All hooks installed successfully!|r")
end

-----------------------------------------------
-- Slash Commands
-----------------------------------------------

SLASH_DDINGUI_SKIN1 = "/ddingskin"
SLASH_DDINGUI_SKIN2 = "/dskin"
SlashCmdList["DDINGUI_SKIN"] = function(msg)
    msg = msg and msg:lower():trim() or ""

    if msg == "on" or msg == "enable" then
        ns.db.enabled = true
        ClassicSkin.enabled = true
        print("|cffffffffDDing|r|cffffa300UI|r |cff8B8000Classic Skin|r: |cff00ff00Enabled|r — /reload to apply")
    elseif msg == "off" or msg == "disable" then
        ns.db.enabled = false
        ClassicSkin.enabled = false
        print("|cffffffffDDing|r|cffffa300UI|r |cff8B8000Classic Skin|r: |cffff4444Disabled|r — /reload to apply")
    elseif msg == "icons" then
        ns.db.skinIcons = not ns.db.skinIcons
        print("|cffffffffDDing|r|cffffa300UI|r |cff8B8000Classic Skin|r: Icons " ..
            (ns.db.skinIcons and "|cff00ff00ON|r" or "|cffff4444OFF|r") .. " — /reload to apply")
    elseif msg == "bars" then
        ns.db.skinBars = not ns.db.skinBars
        print("|cffffffffDDing|r|cffffa300UI|r |cff8B8000Classic Skin|r: Bars " ..
            (ns.db.skinBars and "|cff00ff00ON|r" or "|cffff4444OFF|r") .. " — /reload to apply")
    else
        print("|cffffffffDDing|r|cffffa300UI|r |cff8B8000Classic Skin|r v1.0.0")
        print("  /dskin on|off — 전체 토글")
        print("  /dskin icons — 아이콘 스킨 토글")
        print("  /dskin bars — 바 스킨 토글")
        print("  Current: " ..
            (ClassicSkin.enabled and "|cff00ff00ON|r" or "|cffff4444OFF|r") ..
            " | Icons: " .. (ns.db.skinIcons and "|cff00ff00ON|r" or "|cffff4444OFF|r") ..
            " | Bars: " .. (ns.db.skinBars and "|cff00ff00ON|r" or "|cffff4444OFF|r"))
    end
end

-----------------------------------------------
-- Debug helper
-----------------------------------------------

function ns.Debug(msg)
    if ns.db and ns.db.debug then
        print("|cff808080[ClassicSkin]|r " .. tostring(msg))
    end
end
