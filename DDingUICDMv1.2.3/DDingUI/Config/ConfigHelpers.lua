local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
local L = LibStub("AceLocale-3.0"):GetLocale("DDingUI")

-- ============================================================
-- CONFIG HELPERS - Common option functions used across Config files
-- ============================================================

-- [REFACTOR] AceGUI → StyleLib
-- LSM compatibility shim: AceGUI-3.0-SharedMediaWidgets 제거 후에도
-- AceGUIWidgetLSMlists 글로벌 참조가 동작하도록 LSM:HashTable() 기반 shim 제공
if not AceGUIWidgetLSMlists then
    local LSM = LibStub("LibSharedMedia-3.0")
    AceGUIWidgetLSMlists = {
        font = LSM:HashTable("font"),
        statusbar = LSM:HashTable("statusbar"),
        sound = LSM:HashTable("sound"),
        background = LSM:HashTable("background"),
        border = LSM:HashTable("border"),
    }
end

-- ============================================
-- 폰트 드롭다운 헬퍼 (로케일별 기본 이름 + SharedMedia 전체 목록)
-- ============================================
do
    local LSM = LibStub("LibSharedMedia-3.0")
    -- 로케일별 기본 폰트 이름 (LSM 등록 키)
    DDingUI.DEFAULT_FONT_NAME = LSM:GetDefault("font") or "기본 글꼴"

    -- 영문 키 → 한국어 매핑 (구 SavedVars 호환)
    local FONT_FRIENDLY_NAMES = {
        ["2002"]             = "기본 글꼴",
        ["2002 Bold"]        = "굵은 글꼴",
        ["Friz Quadrata TT"] = "Friz Quadrata TT",
        ["Morpheus"]         = "Morpheus",
        ["Skurri"]           = "Skurri",
        ["Arial Narrow"]     = "Arial Narrow",
    }

    -- 폰트 드롭다운 values 반환 (LSM 전체 목록, 중복 영문 키 제거)
    function DDingUI:GetFontValues()
        local names = {}
        if AceGUIWidgetLSMlists and AceGUIWidgetLSMlists.font then
            for k, v in pairs(AceGUIWidgetLSMlists.font) do
                names[k] = FONT_FRIENDLY_NAMES[k] or k
            end
        end
        return names
    end

    -- 저장된 폰트 키를 현재 로케일에 맞게 보정
    -- (구버전에서 "2002"로 저장된 값 → koKR에서 "기본 글꼴"로 변환)
    function DDingUI:ResolveFontKey(fontKey)
        if not fontKey or fontKey == "" then
            return self.DEFAULT_FONT_NAME
        end
        -- LSM에 이 키가 있으면 그대로 사용
        if LSM:IsValid("font", fontKey) then
            return fontKey
        end
        -- 영문 키 → 한국어 키 매핑 시도
        local mapped = FONT_FRIENDLY_NAMES[fontKey]
        if mapped and LSM:IsValid("font", mapped) then
            return mapped
        end
        return self.DEFAULT_FONT_NAME
    end
end

-- [REFACTOR] AceGUI → StyleLib
-- AceConfigRegistry:NotifyChange() 대체: 커스텀 GUI 새로고침 헬퍼
function DDingUI:RefreshConfigGUI(soft)
    local configFrame = _G["DDingUI_ConfigFrame"]
    if configFrame and configFrame:IsShown() then
        if soft and configFrame.SoftRefresh then
            configFrame:SoftRefresh()
        elseif configFrame.FullRefresh then
            configFrame:FullRefresh()
        end
    end
end

-- Anchor point options (9 standard anchor points)
function DDingUI:GetAnchorOptions()
    return {
        TOPLEFT     = L["Top Left"] or "Top Left",
        TOP         = L["Top"] or "Top",
        TOPRIGHT    = L["Top Right"] or "Top Right",
        LEFT        = L["Left"] or "Left",
        CENTER      = L["Center"] or "Center",
        RIGHT       = L["Right"] or "Right",
        BOTTOMLEFT  = L["Bottom Left"] or "Bottom Left",
        BOTTOM      = L["Bottom"] or "Bottom",
        BOTTOMRIGHT = L["Bottom Right"] or "Bottom Right",
    }
end

-- Viewer options (cooldown viewer frames to attach to)
-- Note: BuffBar is a separate module, not a CooldownViewer
function DDingUI:GetViewerOptions()
    return {
        ["EssentialCooldownViewer"] = L["Essential Cooldowns"] or "Essential Cooldowns",
        ["UtilityCooldownViewer"] = L["Utility Cooldowns"] or "Utility Cooldowns",
        ["BuffIconCooldownViewer"] = L["Buff Icons"] or "Buff Icons",
        ["DDingUIPowerBar"] = L["Primary Power Bar"] or "주 자원바",
        ["DDingUISecondaryPowerBar"] = L["Secondary Power Bar"] or "보조 자원바",
    }
end

-- Extended viewer options (including UIParent)
function DDingUI:GetExtendedViewerOptions()
    local options = self:GetViewerOptions()
    options["UIParent"] = "UIParent"
    return options
end

-- Text alignment options
function DDingUI:GetTextAlignOptions()
    return {
        LEFT = L["Left"] or "Left",
        CENTER = L["Center"] or "Center",
        RIGHT = L["Right"] or "Right",
    }
end

-- Growth direction options
function DDingUI:GetGrowthDirectionOptions()
    return {
        LEFT = L["Left"] or "Left",
        RIGHT = L["Right"] or "Right",
        UP = L["Up"] or "Up",
        DOWN = L["Down"] or "Down",
    }
end

-- Horizontal growth direction options
function DDingUI:GetHorizontalGrowthOptions()
    return {
        LEFT = L["Left"] or "Left",
        RIGHT = L["Right"] or "Right",
    }
end

-- Vertical growth direction options
function DDingUI:GetVerticalGrowthOptions()
    return {
        UP = L["Up"] or "Up",
        DOWN = L["Down"] or "Down",
    }
end

-- Sort options for icon viewers
function DDingUI:GetSortOptions()
    return {
        ASCENDING = L["Ascending"] or "Ascending",
        DESCENDING = L["Descending"] or "Descending",
    }
end

-- ============================================================
-- BUFF TRACKER BAR - Default per-spec config
-- Used by BuffTrackerBar.lua and BuffTrackerOptions.lua
-- ============================================================

-- Default values for per-spec config
local BuffTrackerDefaultSpecConfig = {
    maxStacks = 4,
    stackDuration = 20,
    hideWhenZero = true,
    resetOnCombatEnd = true,
    barFillMode = "stacks",
    trackingMode = "manual",
    attachTo = "EssentialCooldownViewer",
    anchorPoint = "BOTTOM",
    height = 6,
    width = 0,
    offsetX = 0,
    offsetY = -1,
    texture = nil,
    barColor = { 1, 0.8, 0, 1 },
    bgColor = { 0.15, 0.15, 0.15, 1 },
    borderSize = 1,
    borderColor = { 0, 0, 0, 1 },
    showStacksText = true,
    showDurationText = false,
    showTicks = true,
    tickWidth = 2,
    smoothProgress = true,
    onlyInCombat = false,
    textFont = nil,
    textSize = 12,
    textX = 0,
    textY = 0,
    textAlign = "CENTER",
    textColor = { 1, 1, 1, 1 },
    durationTextFont = nil,
    durationTextSize = 10,
    durationTextX = 0,
    durationTextY = -10,
    durationTextAlign = "CENTER",
    durationTextColor = { 1, 1, 1, 1 },
    requireTalentID = 0,
    bonusTalentID = 0,
    bonusTalentStacks = 1,
    generators = {},
    spenders = {},
}

-- Get default spec config (returns a deep copy)
function DDingUI:GetBuffTrackerDefaultSpecConfig()
    local copy = {}
    for k, v in pairs(BuffTrackerDefaultSpecConfig) do
        if type(v) == "table" then
            copy[k] = {}
            for i, val in pairs(v) do
                copy[k][i] = val
            end
        else
            copy[k] = v
        end
    end
    return copy
end

-- Get raw reference (for iteration, not modification)
function DDingUI:GetBuffTrackerDefaultSpecConfigRef()
    return BuffTrackerDefaultSpecConfig
end

-- Expose for namespace access
ns.ConfigHelpers = {
    GetAnchorOptions = function() return DDingUI:GetAnchorOptions() end,
    GetViewerOptions = function() return DDingUI:GetViewerOptions() end,
    GetExtendedViewerOptions = function() return DDingUI:GetExtendedViewerOptions() end,
    GetTextAlignOptions = function() return DDingUI:GetTextAlignOptions() end,
    GetGrowthDirectionOptions = function() return DDingUI:GetGrowthDirectionOptions() end,
    GetHorizontalGrowthOptions = function() return DDingUI:GetHorizontalGrowthOptions() end,
    GetVerticalGrowthOptions = function() return DDingUI:GetVerticalGrowthOptions() end,
    GetSortOptions = function() return DDingUI:GetSortOptions() end,
    GetBuffTrackerDefaultSpecConfig = function() return DDingUI:GetBuffTrackerDefaultSpecConfig() end,
    GetBuffTrackerDefaultSpecConfigRef = function() return DDingUI:GetBuffTrackerDefaultSpecConfigRef() end,
}
