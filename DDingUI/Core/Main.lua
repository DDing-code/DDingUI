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
local CDM_PREFIX = (SL_Main and SL_Main.GetChatPrefix and SL_Main.GetChatPrefix("CDM", "CDM")) or "|cffffffffDDing|r|cffffa300UI|r |cffe6731fCDM|r: " -- [STYLE]

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

    -- [FIX] v3: profile + specData(전문화별 스냅샷) + trackedBuffsPerSpec 함께 번들링
    local exportData = {
        version = 3,
        profile = self.db.profile,
        specData = self.db.char and self.db.char.specData or nil,
        trackedBuffsPerSpec = self.db.global and self.db.global.trackedBuffsPerSpec or nil,
    }

    local serialized = AceSerializer:Serialize(exportData)
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

    -- [FIX] v2/v3 포맷 감지: version 필드가 있으면 wrapper, 없으면 구버전(raw profile)
    local profileData
    local importedTrackedBuffs
    local importedSpecData
    if t.version and t.version >= 2 and t.profile then
        profileData = t.profile
        importedTrackedBuffs = t.trackedBuffsPerSpec
        if t.version >= 3 then
            importedSpecData = t.specData
        end
    else
        -- 구버전 호환: raw profile table
        profileData = t
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

        self.db.profiles[profileName] = profileData
        self.db:SetProfile(profileName)
    else
        -- Old behavior: overwrite current profile safely using AceDB
        if not self.db.profile then
            return false, L["No profile loaded."] or "No profile loaded."
        end
        self.db.profiles["__temp_import__"] = profileData
        self.db:CopyProfile("__temp_import__", true)
        self.db.profiles["__temp_import__"] = nil
    end

    -- [FIX] trackedBuffsPerSpec 복원 (db.global)
    if importedTrackedBuffs and type(importedTrackedBuffs) == "table" then
        if not self.db.global then self.db.global = {} end
        self.db.global.trackedBuffsPerSpec = importedTrackedBuffs
    end

    -- [FIX] v3: specData(전문화별 스냅샷) 복원 (db.char)
    if importedSpecData and type(importedSpecData) == "table" then
        if self.db.char then
            self.db.char.specData = importedSpecData
            self.db.char.specDataProfileKey = self.db:GetCurrentProfile()
        end
    end

    -- [FIX] 프록시 앵커를 새 프로필 위치로 즉시 이동 (RefreshAll 전에 동기적으로 실행)
    -- CreateProxyAnchors에서 (0,0)에 생성된 프록시를 DB 위치로 먼저 옮겨야
    -- 이후 CreateGroupFrame/Refresh에서 프록시를 follow하는 그룹 프레임이 올바른 위치에 표시됨
    do
        local gs = self.db and self.db.profile and self.db.profile.groupSystem
        local PROXY_GROUPS = {
            ["Cooldowns"] = "DDingUI_Anchor_Cooldowns",
            ["Buffs"]     = "DDingUI_Anchor_Buffs",
            ["Utility"]   = "DDingUI_Anchor_Utility",
        }
        if gs and gs.groups then
            for groupName, proxyName in pairs(PROXY_GROUPS) do
                local proxyFrame = _G[proxyName]
                local grp = gs.groups[groupName]
                if proxyFrame and grp then
                    local ox = self:Scale(grp.offsetX or 0)
                    local oy = self:Scale(grp.offsetY or 0)
                    proxyFrame:ClearAllPoints()
                    proxyFrame:SetPoint("CENTER", UIParent, "CENTER", ox, oy)
                end
            end
        end
        -- 등록된 Mover도 새 프로필 위치로 갱신
        if self.Movers and self.Movers.CreatedMovers then
            for moverName, _ in pairs(self.Movers.CreatedMovers) do
                self.Movers:LoadMoverPosition(moverName)
            end
        end
    end

    if self.RefreshAll then
        self:RefreshAll()
    end

    if self.SpecProfiles and self.SpecProfiles.SaveCurrentSpec then
        -- [FIX] OnSpecChanged 호출 금지 — 'first visit' 로직이 임포트된 데이터를 Defaults로 덮어씀
        -- 대신 임포트된 프로필 상태를 현재 spec 스냅샷으로 직접 저장
        local specID = GetSpecialization()
        if specID then
            specID = GetSpecializationInfo(specID)
            if specID then
                self.SpecProfiles.lastSpecID = specID
                self.SpecProfiles:SaveCurrentSpec()
            end
        end
    end

    -- [FIX] 프로필 임포트 후 자동 리로드 — StaticPopup으로 보호 함수 taint 회피
    StaticPopupDialogs["DDINGUI_IMPORT_RELOAD"] = {
        text = "|cffffffffDDing|r|cffffa300UI|r\n\n프로필 불러오기가 완료되었습니다.\nUI를 리로드합니다.",
        button1 = "확인",
        timeout = 0,
        whileDead = true,
        hideOnEscape = false,
        OnAccept = function() ReloadUI() end,
        OnShow = function(self) C_Timer.After(1, function() if self and self:IsShown() then self.button1:Click() end end) end,
    }
    StaticPopup_Show("DDINGUI_IMPORT_RELOAD")

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
        print(CDM_PREFIX .. "|cffff0000" .. (L["DDingUI: Invalid Import String."] or "Invalid Import String.") .. "|r") -- [STYLE]
        return
    end
    local DecompressedInfo = LibDeflate:DecompressDeflate(DecodedInfo)
    if not DecompressedInfo then
        print(CDM_PREFIX .. "|cffff0000" .. (L["DDingUI: Invalid Import String."] or "Invalid Import String.") .. "|r") -- [STYLE]
        return
    end
    local success, profileData = AceSerializer:Deserialize(DecompressedInfo)

    if not success or type(profileData) ~= "table" then
        print(CDM_PREFIX .. "|cffff0000" .. (L["DDingUI: Invalid Import String."] or "Invalid Import String.") .. "|r") -- [STYLE]
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

    -- [CONTROLLER] MediaChanged 콜백 등록 (Controller에서 폰트/텍스처 변경 시 갱신)
    if DDingUI_StyleLib and DDingUI_StyleLib.RegisterCallback then
        DDingUI_StyleLib.RegisterCallback(self, "MediaChanged", function()
            -- 폰트/텍스처 변수 갱신
            SL_Main = _G.DDingUI_StyleLib
            WHITE8 = (SL_Main and SL_Main.Textures and SL_Main.Textures.flat) or "Interface\\Buttons\\WHITE8X8"
        end)
    end

    local defaults = DDingUI.defaults
    if not defaults then
        error("DDingUI: Defaults not loaded! Make sure Core/Defaults.lua is loaded before Core/Main.lua")
    end

    self.db = LibStub("AceDB-3.0"):New("DDingUIDB", defaults, true)

    if not self.db or not self.db.sv then
        error("DDingUI: Failed to initialize database! Check SavedVariables in DDingUI.toc")
    end



    -- [FIX] LibDualSpec 사용 안 함 — DDingUI 자체 SpecProfiles 시스템 사용
    -- BigWigs 등 다른 애드온이 로드한 전역 LibDualSpec이 프로필을 강제 전환하는 버그 방지
    -- (DDingUI.toc에서 LibDualSpec-1.0.lua도 이미 주석 처리됨)

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
    
    self:RegisterChatCommand("dcm", "OpenConfig")      -- [CONTROLLER] /dui → /dcm 변경 (Controller /ddingui 충돌 방지)
    self:RegisterChatCommand("ddcm", "OpenConfig")     -- [CONTROLLER] /ddingui → /ddcm 변경
    self:RegisterChatCommand("ddfly", function()
        local cfg = DDingUI.db and DDingUI.db.profile.general
        local enabled = cfg and cfg.hideWhileFlying
        local flying = IsFlying and IsFlying() or false
        local fh = DDingUI.FlightHide
        local initialized = fh and fh._initialized or false
        local active = fh and fh.isActive or false
        print(CDM_PREFIX .. "|cff00ccffFlightHide 진단|r") -- [STYLE]
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
            -- [FIX] 프록시 앵커를 새 프로필 위치로 즉시 이동 (RefreshAll 전)
            local gs = self.db and self.db.profile and self.db.profile.groupSystem
            if gs and gs.groups then
                local PROXY_GROUPS = {
                    ["Cooldowns"] = "DDingUI_Anchor_Cooldowns",
                    ["Buffs"]     = "DDingUI_Anchor_Buffs",
                    ["Utility"]   = "DDingUI_Anchor_Utility",
                }
                for groupName, proxyName in pairs(PROXY_GROUPS) do
                    local proxyFrame = _G[proxyName]
                    local grp = gs.groups[groupName]
                    if proxyFrame and grp then
                        local ox = self:Scale(grp.offsetX or 0)
                        local oy = self:Scale(grp.offsetY or 0)
                        proxyFrame:ClearAllPoints()
                        proxyFrame:SetPoint("CENTER", UIParent, "CENTER", ox, oy)
                    end
                end
            end
            if self.Movers and self.Movers.CreatedMovers then
                for moverName, _ in pairs(self.Movers.CreatedMovers) do
                    self.Movers:LoadMoverPosition(moverName)
                end
            end
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

    if self.CastBars and self.CastBars.Initialize then self.CastBars:Initialize() end
    if self.ResourceBars and self.ResourceBars.Initialize then self.ResourceBars:Initialize() end
    if self.PartyFrames and self.PartyFrames.Initialize then self.PartyFrames:Initialize() end
    if self.RaidFrames and self.RaidFrames.Initialize then self.RaidFrames:Initialize() end
    if self.AutoUIScale and self.AutoUIScale.Initialize then self.AutoUIScale:Initialize() end
    if self.Chat and self.Chat.Initialize then self.Chat:Initialize() end
    if self.Minimap and self.Minimap.Initialize then self.Minimap:Initialize() end
    if self.ActionBars and self.ActionBars.Initialize then self.ActionBars:Initialize() end

    if self.ActionBarGlow and self.ActionBarGlow.Initialize then
        C_Timer.After(1.0, function()
            self.ActionBarGlow:Initialize()
        end)
    end

    if self.BuffDebuffFrames and self.BuffDebuffFrames.Initialize then self.BuffDebuffFrames:Initialize() end
    if self.MissingAlerts and self.MissingAlerts.Initialize then self.MissingAlerts:Initialize() end
    if self.QOL and self.QOL.Initialize then self.QOL:Initialize() end
    if self.CharacterPanel and self.CharacterPanel.Initialize then self.CharacterPanel:Initialize() end
    
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
                UF.RepositionAllUnitFrames = function(self_, ...)
                    originalReposition(self_, ...)
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


    -- 충돌 가능한 스킨 애드온 감지 및 경고
    C_Timer.After(3.0, function()
        self:CheckSkinConflicts()
    end)

    -- ============================================================
    -- [FIX] 구버전 프로필 마이그레이션 팝업
    -- profileVersion이 없으면 이전 버전 프로필 → 유저에게 마이그레이션 여부 확인
    -- ============================================================
    C_Timer.After(3.5, function()
        if not self.db or not self.db.profile then return end
        if self.db.profile.profileVersion then return end -- 이미 마이그레이션됨

        StaticPopupDialogs["DDINGUI_MIGRATION_PROMPT"] = {
            text = "|cffffffffDDing|r|cffffa300UI|r\n\n이전 버전 프로필이 감지되었습니다.\n앵커 설정을 현재 버전에 맞게\n마이그레이션하시겠습니까?\n\n|cffaaaaaa*업데이트 전과 UI 위치가 달라지지 않았다면\n스킵하셔도 됩니다.|r\n\n|cff00ff00[예]|r 마이그레이션 후 UI 리로드\n|cffff6600[아니오]|r 현재 설정 유지",
            button1 = "예",
            button2 = "아니오",
            timeout = 0,
            whileDead = true,
            hideOnEscape = false,
            OnAccept = function()
                -- 전체 마이그레이션 실행
                if DDingUI.Movers and DDingUI.Movers.MigrateAnchorPoints then
                    DDingUI.Movers:MigrateAnchorPoints()
                end

                -- 보조자원바: 핵심능력 → 주자원바
                local spbCfg = DDingUI.db.profile and DDingUI.db.profile.secondaryPowerBar
                if spbCfg then
                    local old = spbCfg.attachTo
                    if old == "EssentialCooldownViewer" or old == "DDingUI_Anchor_Cooldowns" then
                        spbCfg.attachTo = "DDingUI_PowerBar"
                    end
                end

                -- 리로드
                ReloadUI()
            end,
            OnCancel = function()
                -- 마이그레이션 건너뛰기: profileVersion만 설정
                local addonVersion = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("DDingUI", "Version")
                DDingUI.db.profile.profileVersion = addonVersion or "1.2.4"
                print("|cffffffffDDing|r|cffffa300UI|r |cffe6731fCDM|r: |cffaaaaaaa마이그레이션을 건너뛰었습니다. 설정 > 프로필에서 수동으로 변경할 수 있습니다.|r")
            end,
        }
        StaticPopup_Show("DDINGUI_MIGRATION_PROMPT")
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
        print(CDM_PREFIX .. "|cffff6600" .. list .. "|r 이(가) 쿨다운 뷰어에 스킨을 적용 중입니다.") -- [STYLE]
        print(CDM_PREFIX .. "|cffaaaaaaDDingUI 스킨을 우선 적용합니다. 문제가 지속되면 해당 애드온의 쿨다운 매니저 스킨을 비활성화해 주세요.|r") -- [STYLE]

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


function DDingUI:OpenConfig()
    -- [REFACTOR] AceGUI → StyleLib: AceConfigDialog 폴백 제거
    if self.OpenConfigGUI then
        self:OpenConfigGUI()
    else
        print(CDM_PREFIX .. "|cffff0000Error: Custom GUI not loaded.|r") -- [STYLE]
    end
end

function DDingUI:OpenPartyRaidFramesConfig()
    if self.PartyFrames and self.PartyFrames.ToggleGUI then
        self.PartyFrames:ToggleGUI()
    else
        print(CDM_PREFIX .. "|cffff0000Party/Raid frames GUI not loaded.|r") -- [STYLE]
    end
end

function DDingUI:CheckDualSpec()
    local LibDualSpec = LibStub("LibDualSpec-1.0", true)
    if not LibDualSpec then
        print(CDM_PREFIX .. "|cffff0000LibDualSpec-1.0 is NOT loaded.|r") -- [STYLE]
        print("|cffffff00This is normal on Classic Era realms (except Season of Discovery/Anniversary).|r")
        return
    end
    
    print(CDM_PREFIX .. "|cff00ff00LibDualSpec-1.0 is loaded.|r") -- [STYLE]
    
    if not self.db then
        print(CDM_PREFIX .. "|cffff0000Database not initialized yet.|r") -- [STYLE]
        return
    end
    
    if self.db.IsDualSpecEnabled then
        local isEnabled = self.db:IsDualSpecEnabled()
        print(CDM_PREFIX .. string.format("|cff00ff00Dual Spec support: %s|r", isEnabled and "ENABLED" or "DISABLED")) -- [STYLE]
        
        if isEnabled then
            local currentSpec = GetSpecialization() or 0
            print(CDM_PREFIX .. string.format("|cff00ff00Current spec: %d|r", currentSpec)) -- [STYLE]
            
            local currentProfile = self.db:GetCurrentProfile()
            print(CDM_PREFIX .. string.format("|cff00ff00Current profile: %s|r", currentProfile)) -- [STYLE]
            
            -- Check spec profiles
            for i = 1, 2 do
                local specProfile = self.db:GetDualSpecProfile(i)
                print(CDM_PREFIX .. string.format("|cff00ff00Spec %d profile: %s|r", i, specProfile)) -- [STYLE]
            end
        end
    else
        print(CDM_PREFIX .. "|cffff0000LibDualSpec methods not found on database (database not enhanced).|r") -- [STYLE]
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
            local SL = _G.DDingUI_StyleLib -- [STYLE]
            local title = (SL and SL.CreateAddonTitle) and SL.CreateAddonTitle("CDM", "CooldownManager") or "|cffffffffDDing|r|cffffa300UI|r CDM"
            tooltip:SetText(title)
            tooltip:AddLine("|cffffffffLeft-click|r  Open settings", 0.7, 0.7, 0.7)
            tooltip:AddLine("|cffffffffRight-click|r  Toggle move mode", 0.7, 0.7, 0.7)
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
        -- "인스턴스 밖에서만" 옵션: 인스턴스 안이면 숨기지 않음
        if cfg.hideOutsideInstanceOnly then
            local _, instanceType = IsInInstance()
            if instanceType and instanceType ~= "none" then
                return false
            end
        end
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
    -- [PERF] Mover 프레임은 캐시, ResourceBar는 동적 확인 (지연 생성 대응)
    local _cachedMoverFrames = {}
    local _moverFramesDirty = true

    local function InvalidateOwnedFrames()
        _moverFramesDirty = true
    end

    local function GetOwnedFrames()
        -- Mover 프레임 캐시 갱신 (변경 시에만)
        if _moverFramesDirty then
            wipe(_cachedMoverFrames)
            if DDingUI.Movers and DDingUI.Movers.CreatedMovers then
                for _, holder in pairs(DDingUI.Movers.CreatedMovers) do
                    if holder.parent then
                        _cachedMoverFrames[holder.parent] = true
                    end
                end
            end
            _moverFramesDirty = false
        end

        -- [FIX] ResourceBar 3종은 지연 생성되므로 매번 동적 확인
        -- 테이블 재생성 없이 기존 캐시에 추가만 함
        if DDingUI.powerBar then _cachedMoverFrames[DDingUI.powerBar] = true end
        if DDingUI.secondaryPowerBar then _cachedMoverFrames[DDingUI.secondaryPowerBar] = true end
        if DDingUI.buffTrackerBar then _cachedMoverFrames[DDingUI.buffTrackerBar] = true end

        return _cachedMoverFrames
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
    -- [FIX] GroupSystem 컨테이너 + reparent된 아이콘에도 알파 적용
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

        -- GroupSystem 컨테이너 + UIParent로 reparent된 아이콘 알파 동기화
        local GR = DDingUI.GroupRenderer
        if GR and GR.groupFrames then
            for _, container in pairs(GR.groupFrames) do
                if container and container.SetAlpha then
                    container:SetAlpha(alpha)
                end
                -- reparent된 아이콘은 컨테이너 자식이 아니므로 개별 알파 적용
                if container._managedIcons then
                    for i = 1, (container._iconCount or 0) do
                        local ic = container._managedIcons[i]
                        if ic and ic._ddIsManaged and ic.SetAlpha then
                            ic:SetAlpha(alpha)
                        end
                    end
                end
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
                    FlightHide._hiding = true
                elseif not shouldHide and wasHidden then
                    wasHidden = false
                    targetAlpha = 1
                    FlightHide.isActive = false
                    FlightHide._hiding = false
                    FlightHide._restoring = true  -- [FIX] SkinAllIconsInViewer 훅에서 앵커 리셋 방지
                    debugShown = false
                    ApplyViewerAlpha(1)
                    -- Refresh viewers to restore skinning
                    C_Timer.After(0.3, function()
                        if DDingUI.RefreshViewers then
                            DDingUI:RefreshViewers()
                        end
                    end)
                    -- [FIX] _restoring 해제 (CDM 훅이 DoFullUpdate를 자연 트리거하므로 명시적 호출 불필요)
                    C_Timer.After(1.0, function()
                        FlightHide._restoring = false
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
        -- [PERF] currentAlpha < 1 && == targetAlpha: 이미 숨김 완료. 매 프레임 재적용 불필요
        -- (새 뷰어가 생기면 Show 훅에서 FlightHide가 처리)
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
        FlightHide._restoring = true  -- [FIX] SkinAllIconsInViewer 훅에서 앵커 리셋 방지
        debugShown = false
        ApplyAlpha(1)
        ApplyViewerAlpha(1)
        -- Re-enable OnUpdate so it can self-manage (will remove itself if feature is off)
        self:EnsureOnUpdate()
        if DDingUI.RefreshViewers then
            DDingUI:RefreshViewers()
        end
        -- [FIX] _restoring 해제 (CDM 훅이 DoFullUpdate를 자연 트리거하므로 명시적 호출 불필요)
        C_Timer.After(1.0, function()
            FlightHide._restoring = false
        end)
    end

    function FlightHide:Initialize()
        if self._initialized then return end
        self._initialized = true

        flightHideFrame = CreateFrame("Frame")
        flightHideFrame:SetScript("OnUpdate", FlightHideOnUpdate)
    end
end

function DDingUI:RefreshAll()
    -- [REMOVED] 인라인 ATTACH_MIGRATION 제거
    -- anchorPoint = "CENTER" 강제 리셋이 매 호출마다 실행되어 사용자 앵커 설정을 파괴했음
    -- attachTo 변환: MigrateAnchorPoints (Movers.lua) - 프로필 버전 체크 후 1회만 실행
    -- 런타임 리다이렉트: ResolveAnchorFrame의 ANCHOR_TO_PROXY (Toolkit.lua) - 항상 동작
    local profile = self.db and self.db.profile

    -- [FIX] 프록시 크기 캐시 무효화 → 프로필 전환 시 아이콘 크기 변경 반영
    if self.InvalidateProxySizeCache then
        self:InvalidateProxySizeCache()
    end

    -- [MIGRATION] 구 프로필: 자원바 하나만 있을 때 Y 오프셋 보정
    -- 앵커 기준점이 CENTER→BOTTOM으로 바뀌면서 bar height/2 만큼 밀림 → 보정
    if profile then
        local hasPrimary = profile.powerBar and profile.powerBar.enabled ~= false
        local hasSecondary = profile.secondaryPowerBar and profile.secondaryPowerBar.enabled ~= false
        if hasPrimary and not hasSecondary and profile.powerBar then
            if not profile.powerBar._offsetMigrated then
                local h = profile.powerBar.noSecondaryHeight or profile.powerBar.height or 6
                if self.Scale then h = self:Scale(h) end
                profile.powerBar.offsetY = (profile.powerBar.offsetY or 0) - (h / 2)
                profile.powerBar._offsetMigrated = true
            end
        elseif hasSecondary and not hasPrimary and profile.secondaryPowerBar then
            if not profile.secondaryPowerBar._offsetMigrated then
                local h = profile.secondaryPowerBar.noPrimaryHeight or profile.secondaryPowerBar.height or 4
                if self.Scale then h = self:Scale(h) end
                profile.secondaryPowerBar.offsetY = (profile.secondaryPowerBar.offsetY or 0) - (h / 2)
                profile.secondaryPowerBar._offsetMigrated = true
            end
        end
    end

    -- [MIGRATION] selfPoint / attachTo 기본값 마이그레이션
    -- 구 프로필에는 selfPoint가 없었고, 보조 자원바 attachTo가 프록시였음
    -- AceDB 프록시(self.db.profile)가 아닌 raw 테이블(self.db.profiles[key])에서 확인
    -- AceDB 프록시는 rawget이 항상 nil을 반환하므로 사용 불가
    if profile and self.db and self.db.profiles then
        local currentProfile = self.db:GetCurrentProfile()
        local rawProfile = self.db.profiles[currentProfile]
        if rawProfile then
            local rawPB = rawProfile.powerBar
            local rawSPB = rawProfile.secondaryPowerBar
            local rawCB = rawProfile.castBar
            -- 주 자원바: selfPoint가 없으면 BOTTOM
            if rawPB and rawPB.selfPoint == nil then
                profile.powerBar.selfPoint = "BOTTOM"
            end
            -- 보조 자원바: selfPoint가 없으면 offsetY 기준 판단, attachTo가 없으면 핵심능력(프록시)
            if rawSPB then
                if rawSPB.selfPoint == nil then
                    if rawSPB.offsetY ~= nil then
                        profile.secondaryPowerBar.selfPoint = "CENTER"
                    else
                        profile.secondaryPowerBar.selfPoint = "BOTTOM"
                    end
                end
                if rawSPB.attachTo == nil then
                    profile.secondaryPowerBar.attachTo = "DDingUI_Anchor_Cooldowns"
                end
                -- anchorPoint: offsetY가 저장돼 있으면(사용자 변경) CENTER, 아니면 TOP
                if rawSPB.anchorPoint == nil then
                    if rawSPB.offsetY ~= nil then
                        profile.secondaryPowerBar.anchorPoint = "CENTER"
                    else
                        profile.secondaryPowerBar.anchorPoint = "TOP"
                    end
                end
            end
            -- 시전바: selfPoint가 없으면 CENTER
            if rawCB and rawCB.selfPoint == nil then
                profile.castBar.selfPoint = "CENTER"
            end
        end
    end

    -- [MIGRATION] 구 프로필: 다이나믹 아이콘 그룹의 ElvUF_Player 앵커 폴백
    -- ElvUI 없을 때 앵커가 붕 뜨지 않도록: ElvUF_Player → ddingUI_Player → PlayerFrame
    if profile and profile.groupSystem and profile.groupSystem.groups then
        for groupName, groupSettings in pairs(profile.groupSystem.groups) do
            local attach = groupSettings.attachTo
            if attach and attach == "ElvUF_Player" and not _G["ElvUF_Player"] then
                if _G["ddingUI_Player"] then
                    groupSettings.attachTo = "ddingUI_Player"
                else
                    groupSettings.attachTo = "PlayerFrame"
                end
            end
        end
    end

    self:RefreshViewers()
    -- [FIX] 프로필 변경 시 GroupSystem 레이아웃 재실행
    -- Disable→Enable은 CDM 아이콘을 해제/재수집하여 __cdmIconWidth 타이밍 문제 유발
    -- Refresh만으로 새 설정(iconSize, spacing)으로 레이아웃 갱신 가능
    if self.GroupSystem then
        local gs = self.db and self.db.profile and self.db.profile.groupSystem
        if gs and gs.enabled then
            C_Timer.After(0.3, function()
                if self.GroupSystem.enabled then
                    self.GroupSystem:Refresh()
                else
                    self.GroupSystem:Enable()
                end
                -- Refresh/Enable 완료 후 ResourceBars/CastBars 갱신
                C_Timer.After(0.2, function()
                    if self.ResourceBars and self.ResourceBars.RefreshAll then
                        self.ResourceBars:RefreshAll()
                    end
                    if self.CastBars and self.CastBars.RefreshAll then
                        self.CastBars:RefreshAll()
                    end
                    -- 2차 리프레시: CDM 아이콘 로드 완료 후 최종 너비 반영
                    C_Timer.After(1.5, function()
                        if self.ResourceBars and self.ResourceBars.RefreshAll then
                            self.ResourceBars:RefreshAll()
                        end
                        if self.CastBars and self.CastBars.RefreshAll then
                            self.CastBars:RefreshAll()
                        end
                    end)
                end)
            end)
        else
            -- GroupSystem 비활성 상태면 즉시 Refresh
            if self.ResourceBars and self.ResourceBars.RefreshAll then
                self.ResourceBars:RefreshAll()
            end
            if self.CastBars and self.CastBars.RefreshAll then
                self.CastBars:RefreshAll()
            end
        end
    else
        if self.ResourceBars and self.ResourceBars.RefreshAll then
            self.ResourceBars:RefreshAll()
        end
        if self.CastBars and self.CastBars.RefreshAll then
            self.CastBars:RefreshAll()
        end
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

    -- [FIX] 프로필/스펙 전환 후 모든 Mover 위치 재로드
    -- SpecProfiles:OnSpecChanged → RefreshAll 경로에서
    -- 새 스펙 프로필의 offsetX/Y/attachTo가 Mover에 반영되지 않는 문제 수정
    -- (RegisterMover의 early return으로 LoadMoverPosition 미호출 방지)
    if self.Movers and self.Movers.CreatedMovers then
        for name in pairs(self.Movers.CreatedMovers) do
            self.Movers:LoadMoverPosition(name)
        end
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
        "DDingUICastBar", -- [FIX] 시전바도 프레임 피커에서 직접 선택 가능
        "EssentialCooldownViewer",
        "UtilityCooldownViewer",
        "BuffIconCooldownViewer",
    }

    -- [FIX] GroupSystem 그룹 프레임도 위치 기반 감지에 추가
    if self.Movers and self.Movers.CreatedMovers then
        for name, holder in pairs(self.Movers.CreatedMovers) do
            if name:match("^DDingUI_Group_") and holder.parent and holder.parent:GetName() then
                ddinguiFrames[#ddinguiFrames + 1] = holder.parent:GetName()
            end
        end
    end

    -- 마우스가 프레임 영역 안에 있는지 확인
    local function IsMouseOverFrame(frame)
        if not frame or not frame:IsShown() then return false end
        -- [FIX] alpha=0으로 숨겨진 프레임은 선택 불가 (GroupSystem으로 대체된 CDM 뷰어)
        if frame.GetAlpha and frame:GetAlpha() < 0.01 then return false end
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
                -- [FIX] Mover 오버레이(*_Mover) → 실제 parent 프레임 반환
                local fn = frame:GetName()
                if fn then
                    local moverKey = fn:match("^(.+)_Mover$")
                    if moverKey then
                        local Movers = self.Movers
                        local holder = Movers and Movers.CreatedMovers and Movers.CreatedMovers[moverKey]
                        if holder and holder.parent and holder.parent:GetName() then
                            return holder.parent
                        end
                    end
                end
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
        -- [FIX] _framePickerActive를 즉시 해제하면 마우스 놓기 시 mover OnClick이 발동됨
        -- 0.2초 지연 후 해제하여 OnClick 가드가 작동하게 함
        clickHandled = true  -- Cleanup 후 추가 클릭 처리 방지
        if pickerFrame then
            pickerFrame:Hide()
            pickerFrame:SetScript("OnUpdate", nil)
        end
        -- 클릭 후킹 해제
        if self._framePickerHook then
            self._framePickerHook = nil
        end
        C_Timer.After(0.2, function()
            self._framePickerActive = nil
        end)
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
                    print(CDM_PREFIX .. (L["Frame selected:"] or "선택된 프레임:") .. " |cFFFFFF00" .. frameName .. "|r") -- [STYLE]
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
