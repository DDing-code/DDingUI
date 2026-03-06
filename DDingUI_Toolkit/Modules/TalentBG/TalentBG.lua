--[[
    DDingToolKit - TalentBG Module
    특성창 배경 교체 로직
]]

local addonName, ns = ...
local DDingToolKit = ns.DDingToolKit
local UI = ns.UI

-- TalentBG 모듈
local TalentBG = {}
ns.TalentBG = TalentBG

local isHooked = false

-- 초기화
function TalentBG:OnInitialize()
    -- DB 참조
    self.profileDB = ns.db.profile.TalentBG
    self.charDB = ns.db.char.TalentBG
    self.globalDB = ns.db.global.TalentBG
end

-- 활성화
function TalentBG:OnEnable()
    -- Blizzard_PlayerSpells 로드 확인
    if C_AddOns and C_AddOns.IsAddOnLoaded("Blizzard_PlayerSpells") then
        self:SetupHooks()
    else
        -- 로드 대기
        local frame = CreateFrame("Frame")
        frame:RegisterEvent("ADDON_LOADED")
        frame:SetScript("OnEvent", function(f, event, loadedAddon)
            if loadedAddon == "Blizzard_PlayerSpells" then
                C_Timer.After(0.1, function()
                    self:SetupHooks()
                end)
                f:UnregisterEvent("ADDON_LOADED")
            end
        end)
    end
end

-- 비활성화
function TalentBG:OnDisable()
    -- 특별한 정리 필요 없음 (후킹은 유지)
end

-- 후킹 설정
function TalentBG:SetupHooks()
    if isHooked then return end
    if not PlayerSpellsFrame or not PlayerSpellsFrame.TalentsFrame then return end

    PlayerSpellsFrame.TalentsFrame:HookScript("OnShow", function()
        self:ApplyBackground()
    end)

    isHooked = true

    -- 현재 열려있으면 즉시 적용
    if PlayerSpellsFrame:IsVisible() then
        self:ApplyBackground()
    end
end

-- 현재 배경 가져오기
function TalentBG:GetCurrentBackground()
    local mode = self.profileDB.mode

    if mode == "spec" then
        local spec = GetSpecialization() or 1
        return self.charDB.specSettings[spec] and self.charDB.specSettings[spec].background or ""
    elseif mode == "class" then
        local _, _, classID = UnitClass("player")
        local classSettings = self.globalDB.classSettings[classID]
        return classSettings and classSettings.background or ""
    else  -- global
        return self.profileDB.globalBackground or ""
    end
end

-- 배경 저장
function TalentBG:SetCurrentBackground(texturePath)
    local mode = self.profileDB.mode

    if mode == "spec" then
        local spec = GetSpecialization() or 1
        if not self.charDB.specSettings[spec] then
            self.charDB.specSettings[spec] = {}
        end
        self.charDB.specSettings[spec].background = texturePath
    elseif mode == "class" then
        local _, _, classID = UnitClass("player")
        if not self.globalDB.classSettings[classID] then
            self.globalDB.classSettings[classID] = {}
        end
        self.globalDB.classSettings[classID].background = texturePath
    else  -- global
        self.profileDB.globalBackground = texturePath
    end

    self:ApplyBackground()
    return true
end

-- 모드 설정
function TalentBG:SetMode(mode)
    if mode ~= "spec" and mode ~= "class" and mode ~= "global" then
        return false
    end
    self.profileDB.mode = mode
    self:ApplyBackground()
    return true
end

-- 기본값으로 초기화
function TalentBG:ResetCurrentSettings()
    local mode = self.profileDB.mode

    if mode == "spec" then
        local spec = GetSpecialization() or 1
        if self.charDB.specSettings[spec] then
            self.charDB.specSettings[spec].background = ""
        end
    elseif mode == "class" then
        local _, _, classID = UnitClass("player")
        if self.globalDB.classSettings[classID] then
            self.globalDB.classSettings[classID].background = ""
        end
    else  -- global
        self.profileDB.globalBackground = ""
    end
end

-- 기본 배경 요소 숨기기
local function HideDefaultBackgrounds()
    if not PlayerSpellsFrame then return end

    local talentsFrame = PlayerSpellsFrame.TalentsFrame
    if not talentsFrame then return end

    if PlayerSpellsFrame.Bg then
        PlayerSpellsFrame.Bg:Hide()
    end
    if talentsFrame.Background then
        talentsFrame.Background:SetAlpha(1)
    end
    if talentsFrame.BlackBG then
        talentsFrame.BlackBG:Hide()
    end
    if talentsFrame.AirParticlesClose then
        talentsFrame.AirParticlesClose:SetAlpha(0)
    end
    if talentsFrame.AirParticlesFar then
        talentsFrame.AirParticlesFar:SetAlpha(0)
    end
    if talentsFrame.Clouds1 then
        talentsFrame.Clouds1:SetAlpha(0)
    end
    if talentsFrame.Clouds2 then
        talentsFrame.Clouds2:SetAlpha(0)
    end
    talentsFrame.backgroundAnims = nil
end

-- 배경 적용
function TalentBG:ApplyBackground()
    if not PlayerSpellsFrame or not PlayerSpellsFrame.TalentsFrame then return end

    local texturePath = self:GetCurrentBackground()
    if texturePath and texturePath ~= "" then
        HideDefaultBackgrounds()
        PlayerSpellsFrame.TalentsFrame.Background:SetTexture(texturePath)
    end
    -- 빈 경로면 블리자드 기본 배경 유지
end

-- 배경 업데이트 (외부 호출용)
function TalentBG:UpdateBackground()
    -- Blizzard_PlayerSpells 로드
    if C_AddOns and C_AddOns.LoadAddOn then
        C_AddOns.LoadAddOn("Blizzard_PlayerSpells")
    elseif LoadAddOn then
        LoadAddOn("Blizzard_PlayerSpells")
    end

    if not PlayerSpellsFrame then
        C_Timer.After(0.1, function()
            self:UpdateBackground()
        end)
        return
    end

    self:SetupHooks()
    self:ApplyBackground()
end

-- 모듈 등록
DDingToolKit:RegisterModule("TalentBG", TalentBG)
