local addonName, ns = ...

ns.addonName = addonName
ns.displayName = "DDingUI RaidHelper"

local DEFAULTS = {
    enabled = true,
    locked = true,
    showTooltips = false,
    showUpcomingCooldowns = true,
    countdownVoice = true, -- [STYLE] 리마인더 카운트 켜기/끄기
    countdownVoicePack = "ja", -- [STYLE] 사용자 요청 4종 선택; 기존 일본어 유지
    alertStyle = {}, -- [STYLE] "곧 사용" 알림 세부 옵션 (2026-10-10 사용자 요청); 빈 값은 Timeline 기본값
    windowPast = 12,
    windowFuture = 38,
    timelineScale = 1.0,
    timelineWidth = 680,
    timelineHeight = 98, -- [STYLE] C안: bar + cooldown rail (80~160)
    backgroundAlpha = 1.0,
    optionsScale = 1.0, -- [STYLE] settings-window "GUI 크기"
    cooldownVisibility = {},
    minimap = {
        hide = false,
        minimapPos = 225,
    },
    position = {
        point = "CENTER",
        relativePoint = "CENTER",
        x = 0,
        y = -180,
    },
}

local function CopyDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = {}
            end
            CopyDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

function ns:IsSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value)
end

function ns:Print(...)
    local SL = self:GetStyleLib()
    local prefix = (SL and SL.GetChatPrefix and SL.GetChatPrefix("RaidHelper", "RaidHelper"))
        or "|cffffffffDDing|r|cffffa300UI|r RaidHelper: "
    print(prefix, ...)
end

-- The bundled StyleLib is deliberately private.  A shared LibStub major would
-- allow RaidHelper's copy to become the implementation used by DDingUI/CDM,
-- depending only on addon load order.
function ns:GetStyleLib()
    return _G.DDingUI_RaidHelperStyleLib
end

function ns:Initialize()
    if self.initialized then return end

    DDingUI_RaidHelperDB = DDingUI_RaidHelperDB or {}
    CopyDefaults(DDingUI_RaidHelperDB, DEFAULTS)
    self.db = DDingUI_RaidHelperDB
    -- [STYLE] C안 (2026-10-10): heights >= 170 belong to the old four-row window; same key,
    -- new meaning (bar + rail), so they return to the new default instead of clamping to 160.
    local savedHeight = tonumber(self.db.timelineHeight)
    if not savedHeight or savedHeight >= 170 then
        self.db.timelineHeight = DEFAULTS.timelineHeight
    end

    local styleLib = self:GetStyleLib()
    if styleLib and styleLib.RegisterAddon and styleLib.Colors then
        styleLib.RegisterAddon("RaidHelper", {
            from = { 0.84, 0.36, 1.00, 1.0 },
            to = { 0.45, 0.16, 0.68, 1.0 },
            light = { 0.93, 0.63, 1.00, 1.0 },
            dark = { 0.34, 0.10, 0.50, 1.0 },
        })
    end

    if self.Engine then self.Engine:Initialize() end
    if self.HealerProfileUI then self.HealerProfileUI:Initialize() end
    if self.TimelineUI then self.TimelineUI:Initialize() end
    if self.MinimapButton then self.MinimapButton:Initialize() end
    if self.BigWigsSync then self.BigWigsSync:Initialize() end
    if self.Options then self.Options:Initialize() end
    if self.Commands then self.Commands:Initialize() end

    self.initialized = true
end

local eventFrame = CreateFrame("Frame")
ns.eventFrame = eventFrame

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName then
            ns:Initialize()
            -- [12.0.1] COMBAT_LOG_EVENT(_UNFILTERED) is protected in Midnight.
            -- Live alignment is driven by encounter events and BigWigs messages instead.
            eventFrame:RegisterEvent("ENCOUNTER_START")
            eventFrame:RegisterEvent("ENCOUNTER_END")
            eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
            eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED") -- [STYLE] C12: combat ends edit mode
        elseif ns.initialized and (loadedAddon == "BigWigs" or loadedAddon == "BigWigs_Core") then
            if ns.BigWigsSync then ns.BigWigsSync:Initialize() end
        end
    elseif event == "PLAYER_LOGIN" then
        if ns.initialized and ns.BigWigsSync then ns.BigWigsSync:Initialize() end
    elseif event == "ENCOUNTER_START" then
        if ns.Engine and ns.db and ns.db.enabled then
            if ns.TimelineUI and ns.TimelineUI.IsPreviewMode and ns.TimelineUI:IsPreviewMode() then
                ns.TimelineUI:SetPreviewMode(false, { noReopen = true })
            end
            ns.Engine:StartEncounter(...)
        end
    elseif event == "ENCOUNTER_END" then
        local _, _, _, _, success = ...
        if ns.Engine then ns.Engine:StopEncounter(success == 1) end
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        local unit = ...
        if unit == "player" and ns.Engine then
            ns.Engine:RefreshPlayerSpecialization()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if ns.Options then ns.Options:ApplyPendingSettings() end
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- [STYLE] C12: entering combat ends preview/edit mode; the settings window stays closed.
        if ns.TimelineUI and ns.TimelineUI.IsPreviewMode and ns.TimelineUI:IsPreviewMode() then
            ns.TimelineUI:SetPreviewMode(false, { noReopen = true })
        end
    end
end)
