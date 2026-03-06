local ADDON_NAME, ns = ...

local DDingUI = LibStub("AceAddon-3.0"):NewAddon(
    ADDON_NAME,
    "AceConsole-3.0",
    "AceEvent-3.0"
)

ns.Addon = DDingUI

-- Get localization table (should be loaded by Locales/Locale.lua)
local L = ns.L or LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME, true)

local AceSerializer = LibStub("AceSerializer-3.0", true)
local LibDeflate    = LibStub("LibDeflate", true)
-- AceDBOptions removed to prevent conflicts with ElvUI
local LibDualSpec   = LibStub("LibDualSpec-1.0", true)

local SL_Main = _G.DDingUI_StyleLib -- [12.0.1]
local WHITE8 = (SL_Main and SL_Main.Textures and SL_Main.Textures.flat) or "Interface\\Buttons\\WHITE8X8" -- [12.0.1]

local SELECTION_ALPHA = 0.5
local SelectionRegionKeys = {
    "Center",
    "MouseOverHighlight",
    "TopEdge",
    "BottomEdge",
    "LeftEdge",
    "RightEdge",
    "TopLeft",
    "TopRight",
    "BottomLeft",
    "BottomRight",
    "Left",
    "Right",
    "Top",
    "Bottom",
}

-- IMPORTANT: Use weak table to store DDingUI data instead of adding fields to Blizzard frames
-- This prevents taint propagation that causes secret value errors in WoW 12.0+
local FrameData = setmetatable({}, { __mode = "k" })  -- weak keys

local function GetFrameData(frame)
    if not frame then return nil end
    if not FrameData[frame] then
        FrameData[frame] = {}
    end
    return FrameData[frame]
end

local function IsHooked(frame, hookName)
    local data = FrameData[frame]
    return data and data[hookName]
end

local function SetHooked(frame, hookName)
    GetFrameData(frame)[hookName] = true
end

local function GetBypass(frame, bypassName)
    local data = FrameData[frame]
    return data and data[bypassName]
end

local function SetBypass(frame, bypassName, value)
    GetFrameData(frame)[bypassName] = value
end

local function ApplyAlphaToRegion(region)
    if not region or not region.SetAlpha then
        return
    end

    region:SetAlpha(SELECTION_ALPHA)
    if region.HookScript and not IsHooked(region, "selectionAlphaHooked") then
        SetHooked(region, "selectionAlphaHooked")
        region:HookScript("OnShow", function(self)
            self:SetAlpha(SELECTION_ALPHA)
        end)
    end
end

local function ForceSelectionAlpha(selection)
    if not selection or not selection.SetAlpha then
        return
    end

    SetBypass(selection, "selectionAlphaLock", true)
    selection:SetAlpha(SELECTION_ALPHA)
    SetBypass(selection, "selectionAlphaLock", nil)
end

-- Performance utilities: avoid C++ overhead on already-shown/hidden frames
function DDingUI:SafeShow(frame)
    if frame and not frame:IsShown() then frame:Show() end
end
function DDingUI:SafeHide(frame)
    if frame and frame:IsShown() then frame:Hide() end
end

function DDingUI:ApplySelectionAlpha(selection)
    if not selection then
        return
    end

    ForceSelectionAlpha(selection)

    if selection.HookScript and not IsHooked(selection, "selectionOnShowHooked") then
        SetHooked(selection, "selectionOnShowHooked")
        selection:HookScript("OnShow", function(self)
            DDingUI:ApplySelectionAlpha(self)
        end)
    end

    if selection.SetAlpha and not IsHooked(selection, "selectionAlphaHooked") then
        SetHooked(selection, "selectionAlphaHooked")
        hooksecurefunc(selection, "SetAlpha", function(frame)
            if GetBypass(frame, "selectionAlphaLock") then
                return
            end
            ForceSelectionAlpha(frame)
        end)
    end

    for _, key in ipairs(SelectionRegionKeys) do
        ApplyAlphaToRegion(selection[key])
    end
end

function DDingUI:ApplySelectionAlphaToFrame(frame)
    if not frame then
        return
    end
    if frame.IsForbidden and frame:IsForbidden() then
        return
    end
    if frame.Selection then
        self:ApplySelectionAlpha(frame.Selection)
    end
end

function DDingUI:ApplySelectionAlphaToAllFrames()
    local frame = EnumerateFrames()
    while frame do
        self:ApplySelectionAlphaToFrame(frame)
        frame = EnumerateFrames(frame)
    end
end

function DDingUI:InitializeSelectionAlphaController()
    if self.__selectionAlphaInitialized then
        return
    end
    self.__selectionAlphaInitialized = true

    local function TryHookSelectionMixin()
        if self.__selectionMixinHooked then
            return true
        end
        if EditModeSelectionFrameBaseMixin then
            self.__selectionMixinHooked = true
            hooksecurefunc(EditModeSelectionFrameBaseMixin, "OnLoad", function(selectionFrame)
                DDingUI:ApplySelectionAlpha(selectionFrame)
            end)
            hooksecurefunc(EditModeSelectionFrameBaseMixin, "OnShow", function(selectionFrame)
                DDingUI:ApplySelectionAlpha(selectionFrame)
            end)
            return true
        end
        return false
    end

    if not TryHookSelectionMixin() then
        local waiter = CreateFrame("Frame")
        waiter:RegisterEvent("ADDON_LOADED")
        waiter:SetScript("OnEvent", function(self, _, addonName)
            if addonName == "Blizzard_EditMode" or addonName == ADDON_NAME then
                if TryHookSelectionMixin() then
                    self:UnregisterEvent("ADDON_LOADED")
                    self:SetScript("OnEvent", nil)
                end
            end
        end)
    end

    self:ApplySelectionAlphaToAllFrames()
    C_Timer.After(0.5, function()
        DDingUI:ApplySelectionAlphaToAllFrames()
    end)

    self.SelectionAlphaTicker = C_Timer.NewTicker(1.0, function()
        if EditModeManagerFrame and EditModeManagerFrame.editModeActive then
            DDingUI:ApplySelectionAlphaToAllFrames()
        end
    end)
end

function DDingUI:ExportProfileToString()
    if not self.db or not self.db.profile then
        return L["No profile loaded."] or "No profile loaded."
    end
    if not AceSerializer or not LibDeflate then
        return L["Export requires AceSerializer-3.0 and LibDeflate."] or "Export requires AceSerializer-3.0 and LibDeflate."
    end

    local serialized = AceSerializer:Serialize(self.db.profile)
    if not serialized or type(serialized) ~= "string" then
        return L["Failed to serialize profile."] or "Failed to serialize profile."
    end

    local compressed = LibDeflate:CompressDeflate(serialized)
    if not compressed then
        return L["Failed to compress profile."] or "Failed to compress profile."
    end

    local encoded = LibDeflate:EncodeForPrint(compressed)
    if not encoded then
        return L["Failed to encode profile."] or "Failed to encode profile."
    end

    return "DDUI1:" .. encoded
end

function DDingUI:ImportProfileFromString(str, profileName)
    if not self.db then
        return false, L["No profile loaded."] or "No profile loaded."
    end
    if not AceSerializer or not LibDeflate then
        return false, L["Import requires AceSerializer-3.0 and LibDeflate."] or "Import requires AceSerializer-3.0 and LibDeflate."
    end
    if not str or str == "" then
        return false, L["No data provided."] or "No data provided."
    end

    str = str:gsub("%s+", "")
    str = str:gsub("^DDUI1:", "")

    local compressed = LibDeflate:DecodeForPrint(str)
    if not compressed then
        return false, L["Could not decode string (maybe corrupted)."] or "Could not decode string (maybe corrupted)."
    end

    local serialized = LibDeflate:DecompressDeflate(compressed)
    if not serialized then
        return false, L["Could not decompress data."] or "Could not decompress data."
    end

    local ok, t = AceSerializer:Deserialize(serialized)
    if not ok or type(t) ~= "table" then
        return false, L["Could not deserialize profile."] or "Could not deserialize profile."
    end

    -- If profileName is provided, create a new profile
    if profileName and profileName ~= "" then
        -- Ensure unique name by checking if profile already exists
        local baseName = profileName
        local counter = 1
        while self.db.profiles and self.db.profiles[profileName] do
            counter = counter + 1
            profileName = baseName .. " " .. counter
        end

        -- Create the new profile
        if not self.db.profiles then
            return false, L["Profile system not available."] or "Profile system not available."
        end

        self.db.profiles[profileName] = t
        self.db:SetProfile(profileName)
    else
        -- Old behavior: overwrite current profile (for backwards compatibility)
        if not self.db.profile then
            return false, L["No profile loaded."] or "No profile loaded."
        end
        local profile = self.db.profile
        for k in pairs(profile) do
            profile[k] = nil
        end
        for k, v in pairs(t) do
            profile[k] = v
        end
    end

    if self.RefreshAll then
        self:RefreshAll()
    end

    return true
end

-- Wago UI Pack Installer Integration Functions
function DDingUI:ExportDDingUI(profileKey)
    if not AceSerializer or not LibDeflate then return nil end
    local profile = self.db.profiles[profileKey]
    if not profile then return nil end

    local profileData = { profile = profile, }

    local SerializedInfo = AceSerializer:Serialize(profileData)
    if not SerializedInfo then return nil end
    local CompressedInfo = LibDeflate:CompressDeflate(SerializedInfo)
    if not CompressedInfo then return nil end
    local EncodedInfo = LibDeflate:EncodeForPrint(CompressedInfo)
    if not EncodedInfo then return nil end
    EncodedInfo = "!DDingUI_" .. EncodedInfo
    return EncodedInfo
end

function DDingUI:ImportDDingUI(importString, profileKey)
    if not AceSerializer or not LibDeflate then return end
    if not importString or type(importString) ~= "string" then return end

    local DecodedInfo = LibDeflate:DecodeForPrint(importString:sub(9))
    if not DecodedInfo then
        print("|cFF8080FF" .. (L["DDingUI: Invalid Import String."] or "DDingUI: Invalid Import String.") .. "|r")
        return
    end
    local DecompressedInfo = LibDeflate:DecompressDeflate(DecodedInfo)
    if not DecompressedInfo then
        print("|cFF8080FF" .. (L["DDingUI: Invalid Import String."] or "DDingUI: Invalid Import String.") .. "|r")
        return
    end
    local success, profileData = AceSerializer:Deserialize(DecompressedInfo)

    if not success or type(profileData) ~= "table" then
        print("|cFF8080FF" .. (L["DDingUI: Invalid Import String."] or "DDingUI: Invalid Import String.") .. "|r")
        return
    end

    if type(profileData.profile) == "table" then
        self.db.profiles[profileKey] = profileData.profile
        self.db:SetProfile(profileKey)
    end
end

function DDingUI:OnInitialize()
    -- [STYLE] Register with shared style library
    if DDingUI_StyleLib and DDingUI_StyleLib.RegisterAddon then
        DDingUI_StyleLib.RegisterAddon("CDM")
    end

    local defaults = DDingUI.defaults
    if not defaults then
        error("DDingUI: Defaults not loaded! Make sure Core/Defaults.lua is loaded before Core/Main.lua")
    end

    self.db = LibStub("AceDB-3.0"):New("DDingUIDB", defaults, true)

    if not self.db or not self.db.sv then
        error("DDingUI: Failed to initialize database! Check SavedVariables in DDingUI.toc")
    end

    if LibDualSpec then
        LibDualSpec:EnhanceDatabase(self.db, ADDON_NAME)
    end

    ns.db = self.db

    self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileCopied",  "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileReset",   "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileDeleted", "OnProfileChanged")

    -- Create ShadowUIParent for hiding UI elements
    self.ShadowUIParent = CreateFrame("Frame", nil, UIParent)
    self.ShadowUIParent:Hide()

    self:InitializePixelPerfect()

    -- Per-spec full-profile snapshots (within one AceDB profile)
    if self.SpecProfiles and self.SpecProfiles.Initialize then
        self.SpecProfiles:Initialize()
    end

    self:SetupOptions()
    
    self:RegisterChatCommand("dui", "OpenConfig")
    self:RegisterChatCommand("ddingui", "OpenConfig")
    self:RegisterChatCommand("ddfly", function()
        local cfg = DDingUI.db and DDingUI.db.profile.general
        local enabled = cfg and cfg.hideWhileFlying
        local flying = IsFlying and IsFlying() or false
        local fh = DDingUI.FlightHide
        local initialized = fh and fh._initialized or false
        local active = fh and fh.isActive or false
        print("|cff00ccff[DDingUI FlightHide 진단]|r")
        print("  hideWhileFlying 설정:", enabled and "|cff00ff00ON|r" or "|cffff0000OFF|r")
        print("  IsFlying():", flying and "|cff00ff00true|r" or "|cffff0000false|r")
        print("  FlightHide 초기화:", initialized and "|cff00ff00OK|r" or "|cffff0000NO|r")
        print("  FlightHide.isActive:", active and "|cff00ff00true|r" or "|cffff0000false|r")
        local viewerKeys = DDingUI.viewers or {}
        for _, key in ipairs(viewerKeys) do
            local v = _G[key]
            if v then
                print("  " .. key .. ": alpha=" .. string.format("%.2f", v:GetAlpha()) .. " shown=" .. tostring(v:IsShown()) .. " scale=" .. string.format("%.3f", v:GetScale()))
            else
                print("  " .. key .. ": |cffff0000NOT FOUND|r")
            end
        end
    end)

    self:CreateMinimapButton()
end

function DDingUI:OnProfileChanged(event, db, profileKey)
    if self.RefreshAll then
        -- Defer RefreshAll if in combat to avoid taint/secret value errors
        if InCombatLockdown() then
            if not self.__pendingRefreshAll then
                self.__pendingRefreshAll = true
                local eventFrame = CreateFrame("Frame")
                eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
                eventFrame:SetScript("OnEvent", function(self)
                    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                    if DDingUI.RefreshAll and not InCombatLockdown() then
                        DDingUI:RefreshAll()
                    end
                    DDingUI.__pendingRefreshAll = nil
                end)
            end
        else
            self:RefreshAll()
        end
    end
end

function DDingUI:InitializePixelPerfect()
    self.physicalWidth, self.physicalHeight = GetPhysicalScreenSize()
    self.resolution = string.format('%dx%d', self.physicalWidth, self.physicalHeight)
    self.perfect = 768 / self.physicalHeight
    
    self:UIMult()
    
    self:RegisterEvent('UI_SCALE_CHANGED')
end

function DDingUI:UI_SCALE_CHANGED()
    self:PixelScaleChanged('UI_SCALE_CHANGED')
end

local function StyleMicroButtonRegion(button, region)
    if not (button and region) then
        return
    end
    local data = GetFrameData(region)
    if data.styled then
        return
    end

    data.styled = true
    region:SetTexture(WHITE8)
    region:SetVertexColor(0, 0, 0, 1)
    region:SetAlpha(0.8)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", button, 2.5, -2.5)
    region:SetPoint("BOTTOMRIGHT", button, -2.5, 2.5)
end

local function StyleMicroButton(button)
    if not button then
        return
    end
    StyleMicroButtonRegion(button, button.Background)
    StyleMicroButtonRegion(button, button.PushedBackground)
end

function DDingUI:StyleMicroButtons()
    if type(MICRO_BUTTONS) == "table" then
        for _, name in ipairs(MICRO_BUTTONS) do
            StyleMicroButton(_G[name])
        end
    end
    -- Fallback if MICRO_BUTTONS is missing
    StyleMicroButton(_G.CharacterMicroButton)
end

function DDingUI:PLAYER_LOGIN()
    if self.ApplyGlobalFont then
        self:ApplyGlobalFont()
    end
    self:UnregisterEvent("PLAYER_LOGIN")
end

function DDingUI:OnEnable()
    SetCVar("cooldownViewerEnabled", 1)
    
    if self.UIMult then
        self:UIMult()
    end
    
    if self.ApplyGlobalFont then
        C_Timer.After(0.5, function()
            self:ApplyGlobalFont()
        end)
    end
    
    self:RegisterEvent("PLAYER_LOGIN")
    
    C_Timer.After(0.1, function()
        DDingUI:StyleMicroButtons()
    end)
    
    if self.IconViewers and self.IconViewers.HookViewers then
        self.IconViewers:HookViewers()
    end

    if self.IconViewers and self.IconViewers.BuffBarCooldownViewer and self.IconViewers.BuffBarCooldownViewer.Initialize then
        self.IconViewers.BuffBarCooldownViewer:Initialize()
    end

    if self.ProcGlow and self.ProcGlow.Initialize then
        C_Timer.After(0.1, function()
            self.ProcGlow:Initialize()
        end)
    end

    if self.AssistHighlight and self.AssistHighlight.Initialize then
        C_Timer.After(0.3, function()
            self.AssistHighlight:Initialize()
        end)
    end

    if self.Keybinds and self.Keybinds.Initialize then
        C_Timer.After(1.0, function()
            self.Keybinds:Initialize()
        end)
    end

    if self.CastBars and self.CastBars.Initialize then
        self.CastBars:Initialize()
    end
    
    if self.ResourceBars and self.ResourceBars.Initialize then
        self.ResourceBars:Initialize()
    end

    if self.PartyFrames and self.PartyFrames.Initialize then
        self.PartyFrames:Initialize()
    end

    if self.RaidFrames and self.RaidFrames.Initialize then
        self.RaidFrames:Initialize()
    end
    
    if self.AutoUIScale and self.AutoUIScale.Initialize then
        self.AutoUIScale:Initialize()
    end
    
    if self.Chat and self.Chat.Initialize then
        self.Chat:Initialize()
    end
    
    if self.Minimap and self.Minimap.Initialize then
        self.Minimap:Initialize()
    end
    
    if self.ActionBars and self.ActionBars.Initialize then
        self.ActionBars:Initialize()
    end
    
    if self.ActionBarGlow and self.ActionBarGlow.Initialize then
        C_Timer.After(1.0, function()
            self.ActionBarGlow:Initialize()
        end)
    end
    
    if self.BuffDebuffFrames and self.BuffDebuffFrames.Initialize then
        self.BuffDebuffFrames:Initialize()
    end

    if self.MissingAlerts and self.MissingAlerts.Initialize then
        self.MissingAlerts:Initialize()
    end

    if self.QOL and self.QOL.Initialize then
        self.QOL:Initialize()
    end

    if self.CharacterPanel and self.CharacterPanel.Initialize then
        self.CharacterPanel:Initialize()
    end

    -- Flight Hide System
    if self.FlightHide and self.FlightHide.Initialize then
        self.FlightHide:Initialize()
    end

    -- Target/Focus/Boss cast bars removed - player cast bar only
    
    if self.UnitFrames and self.db.profile.unitFrames and self.db.profile.unitFrames.enabled then
        C_Timer.After(0.5, function()
            if self.UnitFrames.Initialize then
                self.UnitFrames:Initialize()
            end
            
            if self.AbsorbBars and self.AbsorbBars.Initialize then
                self.AbsorbBars:Initialize()
            end
            
            local UF = self.UnitFrames
            if UF and UF.RepositionAllUnitFrames then
                local originalReposition = UF.RepositionAllUnitFrames
                UF.RepositionAllUnitFrames = function(self, ...)
                    originalReposition(self, ...)
                    C_Timer.After(0.1, function()
                        if DDingUI.CustomIcons and DDingUI.CustomIcons.ApplyCustomIconsLayout then
                            DDingUI.CustomIcons:ApplyCustomIconsLayout()
                        end
                        if DDingUI.CustomIcons and DDingUI.CustomIcons.ApplyTrinketsLayout then
                            DDingUI.CustomIcons:ApplyTrinketsLayout()
                        end
                    end)
                end
            end
        end)
    end
    
    if self.IconViewers and self.IconViewers.AutoLoadBuffIcons then
        C_Timer.After(0.5, function()
            self.IconViewers:AutoLoadBuffIcons()
        end)
    end

    -- Ensure all viewers are skinned on load
    if self.IconViewers and self.IconViewers.RefreshAll then
        C_Timer.After(1.0, function()
            self.IconViewers:RefreshAll()
        end)
    end
    
    if self.CustomIcons then
        C_Timer.After(1.5, function()
            if self.CustomIcons.CreateCustomIconsTrackerFrame then
                self.CustomIcons:CreateCustomIconsTrackerFrame()
            end
            if self.CustomIcons.CreateTrinketsTrackerFrame then
                self.CustomIcons:CreateTrinketsTrackerFrame()
            end
            if self.CustomIcons.CreateDefensivesTrackerFrame then
                self.CustomIcons:CreateDefensivesTrackerFrame()
            end
        end)

        C_Timer.After(2.5, function()
            if self.CustomIcons.ApplyCustomIconsLayout then
                self.CustomIcons:ApplyCustomIconsLayout()
            end
            if self.CustomIcons.ApplyTrinketsLayout then
                self.CustomIcons:ApplyTrinketsLayout()
            end
            if self.CustomIcons.ApplyDefensivesLayout then
                self.CustomIcons:ApplyDefensivesLayout()
            end
        end)
    end

    self:InitializeSelectionAlphaController()

    -- [REFACTOR] AceGUI → StyleLib: HookAceGUISliders() 제거 (AceGUI 더 이상 사용 안 함)

    -- 충돌 가능한 스킨 애드온 감지 및 경고
    C_Timer.After(3.0, function()
        self:CheckSkinConflicts()
    end)
end

-- 아이콘 스킨 충돌 감지
do
    -- 실제 스킨 적용 여부 확인 함수
    local function IsElvUISkinningCDM()
        -- ElvUI가 쿨다운 뷰어 스킨을 활성화했는지 확인
        if not ElvUI then return false end
        local E = ElvUI[1]
        if not E or not E.private then return false end
        -- ElvUI의 Blizzard Skins > Cooldown Viewer 옵션 확인
        local skins = E.private.skins
        if skins and skins.blizzard then
            -- cooldownViewer 옵션이 명시적으로 true인 경우만
            if skins.blizzard.cooldownViewer == true then
                return true
            end
        end
        return false
    end

    function DDingUI:CheckSkinConflicts()
        local found = {}

        -- ElvUI 스킨 충돌만 감지
        if IsElvUISkinningCDM() then
            found[#found + 1] = "ElvUI"
        end

        if #found == 0 then return end

        self._skinConflictAddons = found

        -- 경고 메시지
        local list = table.concat(found, ", ")
        print("|cff00ccffDDingUI|r: |cffff6600" .. list .. "|r 이(가) 쿨다운 뷰어에 스킨을 적용 중입니다.")
        print("|cff00ccffDDingUI|r: |cffaaaaaaDDingUI 스킨을 우선 적용합니다. 문제가 지속되면 해당 애드온의 쿨다운 매니저 스킨을 비활성화해 주세요.|r")

        -- 다른 애드온이 스킨 적용 후 DDingUI 스킨 강제 재적용
        if self.IconViewers and self.IconViewers.ForceReskinAll then
            self.IconViewers:ForceReskinAll()
            -- 추가 딜레이 재적용 (일부 애드온은 더 늦게 스킨 적용)
            C_Timer.After(2.0, function()
                if self.IconViewers and self.IconViewers.ForceReskinAll then
                    self.IconViewers:ForceReskinAll()
                end
            end)
        end
    end
end

-- [REFACTOR] AceGUI → StyleLib: HookAceGUISliders 전체 제거
-- AceGUI-3.0을 더 이상 사용하지 않으므로 슬라이더 훅 불필요

function DDingUI:OpenConfig()
    -- [REFACTOR] AceGUI → StyleLib: AceConfigDialog 폴백 제거
    if self.OpenConfigGUI then
        self:OpenConfigGUI()
    else
        print("|cffff0000[DDingUI] Error: Custom GUI not loaded.|r")
    end
end

function DDingUI:OpenPartyRaidFramesConfig()
    if self.PartyFrames and self.PartyFrames.ToggleGUI then
        self.PartyFrames:ToggleGUI()
    else
        print("|cffff0000[DDingUI] Party/Raid frames GUI not loaded.|r")
    end
end

function DDingUI:CheckDualSpec()
    local LibDualSpec = LibStub("LibDualSpec-1.0", true)
    if not LibDualSpec then
        print("|cffff0000[DDingUI] LibDualSpec-1.0 is NOT loaded.|r")
        print("|cffffff00This is normal on Classic Era realms (except Season of Discovery/Anniversary).|r")
        return
    end
    
    print("|cff00ff00[DDingUI] LibDualSpec-1.0 is loaded.|r")
    
    if not self.db then
        print("|cffff0000[DDingUI] Database not initialized yet.|r")
        return
    end
    
    if self.db.IsDualSpecEnabled then
        local isEnabled = self.db:IsDualSpecEnabled()
        print(string.format("|cff00ff00[DDingUI] Dual Spec support: %s|r", isEnabled and "ENABLED" or "DISABLED"))
        
        if isEnabled then
            local currentSpec = GetSpecialization() or 0
            print(string.format("|cff00ff00[DDingUI] Current spec: %d|r", currentSpec))
            
            local currentProfile = self.db:GetCurrentProfile()
            print(string.format("|cff00ff00[DDingUI] Current profile: %s|r", currentProfile))
            
            -- Check spec profiles
            for i = 1, 2 do
                local specProfile = self.db:GetDualSpecProfile(i)
                print(string.format("|cff00ff00[DDingUI] Spec %d profile: %s|r", i, specProfile))
            end
        end
    else
        print("|cffff0000[DDingUI] LibDualSpec methods not found on database (database not enhanced).|r")
    end
end

function DDingUI:CreateMinimapButton()
    local LDB = LibStub("LibDataBroker-1.1", true)
    local LibDBIcon = LibStub("LibDBIcon-1.0", true)
    
    if not LDB or not LibDBIcon then
        return
    end
    
    if not self.db.profile.minimap then
        self.db.profile.minimap = {
            hide = false,
        }
    end
    
    local dataObj = LDB:NewDataObject(ADDON_NAME, {
        type = "launcher",
        icon = "Interface\\AddOns\\DDingUI\\Media\\logo.tga",
        label = L["DDingUI"] or "DDingUI",
        OnClick = function(clickedframe, button)
            if button == "LeftButton" then
                self:OpenConfig()
            elseif button == "RightButton" then
                if self.Movers and self.Movers.ToggleConfigMode then
                    self.Movers:ToggleConfigMode()
                end
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:SetText(L["DDingUI"] or "DDingUI")
            tooltip:AddLine(L["Left-click to open configuration"] or "Left-click to open configuration", 1, 1, 1)
            tooltip:AddLine(L["Right-click to toggle move mode"] or "Right-click to toggle move mode", 1, 1, 1)
        end,
    })
    
    LibDBIcon:Register(ADDON_NAME, dataObj, self.db.profile.minimap)
end

function DDingUI:RefreshViewers()
    if self.IconViewers and self.IconViewers.RefreshAll then
        self.IconViewers:RefreshAll()
    end

    if self.ProcGlow and self.ProcGlow.RefreshAll then
        self.ProcGlow:RefreshAll()
    end
end

function DDingUI:RefreshCustomIcons()
    if not (self.CustomIcons and self.db and self.db.profile and self.db.profile.customIcons) then
        return
    end
    if self.db.profile.customIcons.enabled == false then
        return
    end

    local module = self.CustomIcons
    if module.CreateCustomIconsTrackerFrame then
        module:CreateCustomIconsTrackerFrame()
    end
end

-- ============================================================
-- FLIGHT HIDE SYSTEM
-- Fade out all DDingUI frames when flying / mounted / in vehicle
-- ============================================================
do
    local FlightHide = {}
    DDingUI.FlightHide = FlightHide
    FlightHide.isActive = false

    local wasHidden = false
    local currentAlpha = 1
    local targetAlpha = 1
    local FADE_DURATION = 0.5
    local CHECK_INTERVAL = 0.5
    local checkElapsed = 0
    local debugShown = false
    local abs = math.abs

    local flightHideFrame = nil  -- reference to the OnUpdate frame

    -- Check if any hide condition is met
    local function ShouldHide(cfg)
        if cfg.hideWhileFlying and IsFlying() then return true end
        if cfg.hideWhileMounted and IsMounted() then return true end
        if cfg.hideInVehicle and UnitInVehicle("player") then return true end
        return false
    end

    -- Check if any hide feature is enabled
    local function AnyFeatureEnabled(cfg)
        return cfg.hideWhileFlying or cfg.hideWhileMounted or cfg.hideInVehicle
    end

    -- Collect all DDingUI managed frames (non-viewer)
    local function GetOwnedFrames()
        local frames = {}
        if DDingUI.Movers and DDingUI.Movers.CreatedMovers then
            for _, holder in pairs(DDingUI.Movers.CreatedMovers) do
                if holder.parent then
                    frames[holder.parent] = true
                end
            end
        end
        if DDingUI.powerBar then frames[DDingUI.powerBar] = true end
        if DDingUI.secondaryPowerBar then frames[DDingUI.secondaryPowerBar] = true end
        if DDingUI.buffTrackerBar then frames[DDingUI.buffTrackerBar] = true end
        return frames
    end

    local function ApplyAlpha(alpha)
        local owned = GetOwnedFrames()
        for frame in pairs(owned) do
            if frame.SetAlpha then
                frame:SetAlpha(alpha)
            end
        end
    end

    -- Apply alpha to CDM viewer frames (viewer + viewerFrame + children)
    local function ApplyViewerAlpha(alpha)
        local viewerKeys = DDingUI.viewers or {}
        local count = 0
        for _, key in ipairs(viewerKeys) do
            local viewer = _G[key]
            if viewer then
                viewer:SetAlpha(alpha)
                local vf = viewer.viewerFrame
                if vf and vf.SetAlpha then
                    vf:SetAlpha(alpha)
                end
                count = count + 1
            end
        end
        return count
    end

    -- The OnUpdate handler as a named function
    local function FlightHideOnUpdate(_, elapsed)
        local cfg = DDingUI.db and DDingUI.db.profile.general
        if not cfg or not AnyFeatureEnabled(cfg) then
            if currentAlpha < 1 or FlightHide.isActive then
                FlightHide.isActive = false
                targetAlpha = 1
                debugShown = false
                ApplyViewerAlpha(1)
            else
                -- All features disabled, alpha fully restored, not active -> remove OnUpdate
                if flightHideFrame then
                    flightHideFrame:SetScript("OnUpdate", nil)
                end
                return
            end
        else
            checkElapsed = checkElapsed + elapsed
            if checkElapsed >= CHECK_INTERVAL then
                checkElapsed = 0
                local shouldHide = ShouldHide(cfg)
                if shouldHide and not wasHidden then
                    wasHidden = true
                    targetAlpha = 0
                elseif not shouldHide and wasHidden then
                    wasHidden = false
                    targetAlpha = 1
                    FlightHide.isActive = false
                    debugShown = false
                    ApplyViewerAlpha(1)
                    -- Refresh viewers to restore skinning
                    C_Timer.After(0.3, function()
                        if DDingUI.RefreshViewers then
                            DDingUI:RefreshViewers()
                        end
                    end)
                end
            end
        end

        -- Smooth interpolation
        if currentAlpha ~= targetAlpha then
            local speed = elapsed / FADE_DURATION
            local diff = targetAlpha - currentAlpha
            if abs(diff) <= speed then
                currentAlpha = targetAlpha
            else
                currentAlpha = currentAlpha + (diff > 0 and speed or -speed)
            end
            ApplyAlpha(currentAlpha)
            ApplyViewerAlpha(currentAlpha)
            if currentAlpha == 0 then
                FlightHide.isActive = true
            end
        elseif currentAlpha < 1 then
            -- Re-apply every frame while hidden
            ApplyViewerAlpha(0)
        end
    end

    -- Re-enable the OnUpdate (called when config changes)
    function FlightHide:EnsureOnUpdate()
        if flightHideFrame then
            flightHideFrame:SetScript("OnUpdate", FlightHideOnUpdate)
        end
    end

    function FlightHide:ForceShow()
        wasHidden = false
        targetAlpha = 1
        currentAlpha = 1
        FlightHide.isActive = false
        debugShown = false
        ApplyAlpha(1)
        ApplyViewerAlpha(1)
        -- Re-enable OnUpdate so it can self-manage (will remove itself if feature is off)
        self:EnsureOnUpdate()
        if DDingUI.RefreshViewers then
            DDingUI:RefreshViewers()
        end
    end

    function FlightHide:Initialize()
        if self._initialized then return end
        self._initialized = true

        flightHideFrame = CreateFrame("Frame")
        flightHideFrame:SetScript("OnUpdate", FlightHideOnUpdate)
    end
end

function DDingUI:RefreshAll()
    self:RefreshViewers()
    
    if self.ResourceBars and self.ResourceBars.RefreshAll then
        self.ResourceBars:RefreshAll()
    end
    
    if self.CastBars and self.CastBars.RefreshAll then
        self.CastBars:RefreshAll()
    end
    
    if self.Chat and self.Chat.RefreshAll then
        self.Chat:RefreshAll()
    end
    
    if self.ActionBars and self.ActionBars.RefreshAll then
        self.ActionBars:RefreshAll()
    end
    
    if self.BuffDebuffFrames and self.BuffDebuffFrames.RefreshAll then
        self.BuffDebuffFrames:RefreshAll()
    end

    if self.QOL and self.QOL.Refresh then
        self.QOL:Refresh()
    end

    if self.CharacterPanel and self.CharacterPanel.Refresh then
        self.CharacterPanel:Refresh()
    end
    
    if self.UnitFrames and self.UnitFrames.RefreshFrames then
        self.UnitFrames:RefreshFrames()
    end

    if self.PartyFrames and self.PartyFrames.Refresh then
        self.PartyFrames:Refresh()
    end

    if self.RaidFrames and self.RaidFrames.Refresh then
        self.RaidFrames:Refresh()
    end
    
    if self.Minimap and self.Minimap.Refresh then
        self.Minimap:Refresh()
    end
    
    if self.CustomIcons and self.db.profile.customIcons and self.db.profile.customIcons.enabled ~= false then
        self:RefreshCustomIcons()
    end
end

-- 프레임 선택 피커 (WeakAuras 스타일)
function DDingUI:StartFramePicker(callback)
    if self._framePickerActive then return end
    self._framePickerActive = true

    local L = LibStub("AceLocale-3.0"):GetLocale("DDingUI")

    -- DDingUI의 마우스 비활성화 프레임들 (위치 기반으로 확인)
    local ddinguiFrames = {
        "DDingUIPowerBar",
        "DDingUISecondaryPowerBar",
        "DDingUIBuffTrackerBar",
        "EssentialCooldownViewer",
        "UtilityCooldownViewer",
        "BuffIconCooldownViewer",
    }

    -- 마우스가 프레임 영역 안에 있는지 확인
    local function IsMouseOverFrame(frame)
        if not frame or not frame:IsShown() then return false end
        local scale = frame:GetEffectiveScale()
        local x, y = GetCursorPosition()
        x, y = x / scale, y / scale
        local left, bottom, width, height = frame:GetRect()
        if not left then return false end
        local right, top = left + width, bottom + height
        return x >= left and x <= right and y >= bottom and y <= top
    end

    -- 현재 마우스 아래 프레임 찾기 (피커 프레임 제외)
    local function GetFrameUnderMouse(excludeFrame)
        -- 먼저 DDingUI의 마우스 비활성화 프레임들을 위치 기반으로 확인
        for _, frameName in ipairs(ddinguiFrames) do
            local frame = _G[frameName]
            if frame and IsMouseOverFrame(frame) then
                return frame
            end
        end

        -- 그 다음 일반 마우스 포커스 확인
        local mouseFoci = GetMouseFoci()
        if not mouseFoci then return nil end
        for _, frame in ipairs(mouseFoci) do
            if frame and frame ~= excludeFrame and frame ~= WorldFrame then
                return frame
            end
        end
        return nil
    end

    -- 풀스크린 오버레이 (마우스 이벤트는 통과시킴)
    local pickerFrame = CreateFrame("Frame", "DDingUIFramePicker", UIParent)
    pickerFrame:SetFrameStrata("TOOLTIP")
    pickerFrame:SetAllPoints(UIParent)
    pickerFrame:EnableMouse(false)  -- 마우스 이벤트 통과

    -- 안내 텍스트 (화면 상단)
    local hint = pickerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    hint:SetPoint("TOP", pickerFrame, "TOP", 0, -50)
    hint:SetText(L["Click on a frame to select it (ESC to cancel)"] or "프레임을 클릭하세요 (ESC로 취소)")
    hint:SetTextColor(1, 1, 0, 1)

    -- 하이라이트 프레임
    local highlight = CreateFrame("Frame", nil, pickerFrame, "BackdropTemplate")
    highlight:SetBackdrop({edgeFile = WHITE8, edgeSize = 2})
    highlight:SetBackdropBorderColor(0, 1, 0, 0.8)
    highlight:Hide()

    -- 프레임 이름 표시
    local nameLabel = pickerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetPoint("BOTTOM", highlight, "TOP", 0, 5)
    nameLabel:SetTextColor(0, 1, 0, 1)

    local currentFrame = nil
    local clickHandled = false  -- 클릭 중복 방지

    local function Cleanup()
        self._framePickerActive = nil
        clickHandled = true  -- Cleanup 후 추가 클릭 처리 방지
        if pickerFrame then
            pickerFrame:Hide()
            pickerFrame:SetScript("OnUpdate", nil)
        end
        -- 클릭 후킹 해제
        if self._framePickerHook then
            self._framePickerHook = nil
        end
    end

    -- 마우스 이동 시 하이라이트
    pickerFrame:SetScript("OnUpdate", function()
        local focusFrame = GetFrameUnderMouse(pickerFrame)
        if focusFrame then
            local frameName = focusFrame:GetName()
            if frameName then
                currentFrame = focusFrame
                highlight:ClearAllPoints()
                highlight:SetPoint("TOPLEFT", focusFrame, "TOPLEFT", -2, 2)
                highlight:SetPoint("BOTTOMRIGHT", focusFrame, "BOTTOMRIGHT", 2, -2)
                highlight:Show()
                nameLabel:SetText(frameName)
            else
                -- 이름 없는 프레임 - 부모 찾기
                local parent = focusFrame:GetParent()
                while parent and not parent:GetName() do
                    parent = parent:GetParent()
                end
                if parent and parent:GetName() then
                    currentFrame = parent
                    highlight:ClearAllPoints()
                    highlight:SetPoint("TOPLEFT", parent, "TOPLEFT", -2, 2)
                    highlight:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 2, -2)
                    highlight:Show()
                    nameLabel:SetText(parent:GetName())
                else
                    currentFrame = nil
                    highlight:Hide()
                    nameLabel:SetText("")
                end
            end
        else
            currentFrame = nil
            highlight:Hide()
            nameLabel:SetText("")
        end

        -- ESC 체크
        if IsKeyDown("ESCAPE") then
            Cleanup()
            return
        end

        -- 마우스 클릭 체크 (중복 처리 방지)
        if clickHandled then return end
        if IsMouseButtonDown("LeftButton") then
            if currentFrame then
                local frameName = currentFrame:GetName()
                if frameName and callback then
                    clickHandled = true
                    Cleanup()
                    callback(frameName)
                    -- 선택 확인 메시지
                    print("|cFF00FF00[DDingUI]|r " .. (L["Frame selected:"] or "선택된 프레임:") .. " |cFFFFFF00" .. frameName .. "|r")
                    -- [REFACTOR] AceGUI → StyleLib: 설정 UI 새로고침
                    C_Timer.After(0.1, function()
                        DDingUI:RefreshConfigGUI()
                    end)
                    return
                end
            end
            Cleanup()
        elseif IsMouseButtonDown("RightButton") then
            Cleanup()
        end
    end)
end
