--[[
    DDingToolKit - MythicPlusHelper Module
    신화+ 던전 UI 개선 (WeakAura 방식 구현)
    - 던전 아이콘에 이름/단수/점수 오버레이
    - 클릭 시 텔레포트
]]

local addonName, ns = ...
local DDingToolKit = ns.DDingToolKit
local L = ns.L
local SL = _G.DDingUI_StyleLib -- [12.0.1]
local SL_FONT = (SL and SL.Font and SL.Font.path) or "Fonts\\2002.TTF" -- [12.0.1]
local CHAT_PREFIX = (SL and SL.GetChatPrefix) and SL.GetChatPrefix("MJToolkit", "Toolkit") or "|cffffffffDDing|r|cffffa300UI|r |cff33bfe6Toolkit|r: " -- [STYLE]

local MythicPlusHelper = {}
ns.MythicPlusHelper = MythicPlusHelper

-- 던전 이름 약어 (한글)
local MAP_NAMES = {
    -- The War Within Season 3
    [542] = "알다니",    -- Eco-Dome Al'dani
    [525] = "수문",      -- Operation: Floodgate
    [506] = "BREW",      -- Cinderbrew Meadery
    [505] = "새벽인도자", -- The Dawnbreaker
    [504] = "DFC",       -- Darkflame Cleft
    [503] = "아라카라",   -- Ara-Kara, City of Echoes
    [502] = "CoT",       -- City of Threads
    [501] = "SV",        -- The Stonevault
    [500] = "ROOK",      -- The Rookery
    [499] = "수도원",     -- Priory of the Sacred Flame

    -- Dragonflight
    [464] = "RISE",      -- Murozond's Rise
    [463] = "FALL",      -- Galakrond's Fall
    [406] = "HoI",       -- Halls of Infusion
    [405] = "BH",        -- Brackenhide Hollow
    [404] = "NELT",      -- Neltharus
    [403] = "ULD",       -- Uldaman: Legacy of Tyr
    [402] = "AA",        -- Algeth'ar Academy
    [401] = "AV",        -- The Azure Vault
    [400] = "NO",        -- The Nokhud Offensive
    [399] = "RLP",       -- Ruby Life Pools

    -- Shadowlands
    [392] = "소레아",     -- Tazavesh: So'leah's Gambit
    [391] = "경이",      -- Tazavesh: Streets of Wonder
    [382] = "ToP",       -- Theater of Pain
    [378] = "속죄",      -- Halls of Atonement
    [376] = "NW",        -- The Necrotic Wake
    [375] = "MISTS",     -- Mists of Tirna Scithe

    -- Cataclysm
    [507] = "GB",        -- Grim Batol
    [456] = "TOTT",      -- Throne of the Tides
    [438] = "VP",        -- The Vortex Pinnacle
}

-- 던전별 텔레포트 스펠 ID
local MAP_TO_SPELL = {
    -- The War Within
    [503] = {445417},    -- Ara-Kara
    [506] = {445440},    -- Cinderbrew Meadery
    [502] = {445416},    -- City of Threads
    [504] = {445441},    -- Darkflame Cleft
    [499] = {445444},    -- Priory of the Sacred Flame
    [505] = {445414},    -- The Dawnbreaker
    [500] = {445443},    -- The Rookery
    [501] = {445269},    -- The Stonevault
    [525] = {1216786},   -- Operation: Floodgate
    [542] = {1237215},   -- Eco-Dome Al'dani

    -- Cataclysm
    [507] = {445424},    -- Grim Batol
    [438] = {410080},    -- The Vortex Pinnacle
    [456] = {424142},    -- Throne of the Tides

    -- Dragonflight
    [402] = {393273},    -- Algeth'ar Academy
    [405] = {393267},    -- Brackenhide Hollow
    [463] = {424197},    -- Dawn of the Infinite: Galakrond's Fall
    [464] = {424197},    -- Dawn of the Infinite: Murozond's Rise
    [406] = {393283},    -- Halls of Infusion
    [404] = {393276},    -- Neltharus
    [399] = {393256},    -- Ruby Life Pools
    [401] = {393279},    -- The Azure Vault
    [400] = {393262},    -- The Nokhud Offensive
    [403] = {393222},    -- Uldaman: Legacy of Tyr

    -- Shadowlands
    [377] = {354468},    -- De Other Side
    [378] = {354465},    -- Halls of Atonement
    [375] = {354464},    -- Mists of Tirna Scithe
    [376] = {354462},    -- The Necrotic Wake
    [382] = {354467},    -- Theater of Pain
    [392] = {367416},    -- Tazavesh: So'leah's Gambit
    [391] = {367416},    -- Tazavesh: Streets of Wonder

    -- Legion
    [199] = {424153},    -- Black Rook Hold
    [210] = {393766},    -- Court of Stars
    [198] = {424163},    -- Darkheart Thicket
    [200] = {393764},    -- Halls of Valor
    [206] = {410078},    -- Neltharion's Lair
}

-- 점수 색상
local LEVEL_COLORS = {
    [0] = "ffffffff", -- white
    [1] = "ff1eff00", -- green
    [2] = "ff0070dd", -- blue
    [3] = "ffa335ee", -- purple
    [4] = "ffff8000", -- orange
    [5] = "ffe6cc80", -- gold
}

-- 로컬 변수
local isEnabled = false
local isHooked = false
local dungeonOverlays = {}
local weeklyCountText = nil
local overlaysVisible = true
local textScale = 1.0
local teleportUpdateTimer = nil

-- 스펠 상태
local SpellStatus = {
    Ready = 1,
    OnCooldown = 2,
    NotLearned = 3,
}

-- 초기화
function MythicPlusHelper:OnInitialize()
    if ns.db and ns.db.profile then
        self.db = ns.db.profile.MythicPlusHelper
    end
end

-- 활성화
function MythicPlusHelper:OnEnable()
    if not self.db then
        if ns.db and ns.db.profile and ns.db.profile.MythicPlusHelper then
            self.db = ns.db.profile.MythicPlusHelper
        else
            self.db = {
                showTeleports = true,
                showScore = true,
                scale = 1.0,
            }
        end
    end

    isEnabled = true
    textScale = self.db.scale or 1.0
    overlaysVisible = self.db.enabled ~= false
    self:HookChallengesFrame()

    print(CHAT_PREFIX .. L["MYTHICPLUS_ENABLED_MSG"]) -- [STYLE]
end

-- 비활성화
function MythicPlusHelper:OnDisable()
    isEnabled = false
    self:HideAllOverlays()
end

-- 오버레이 표시/숨김 토글
function MythicPlusHelper:SetOverlaysVisible(visible)
    overlaysVisible = visible
    if self.db then
        self.db.enabled = visible
    end

    if visible then
        self:ShowAllOverlays()
    else
        self:HideAllOverlays()
    end
end

-- 모든 오버레이 숨기기
function MythicPlusHelper:HideAllOverlays()
    for dungeonIcon, overlay in pairs(dungeonOverlays) do
        if overlay.nameText then overlay.nameText:Hide() end
        if overlay.levelText then overlay.levelText:Hide() end
        if overlay.scoreText then overlay.scoreText:Hide() end
        if overlay.teleportButton then overlay.teleportButton:Hide() end

        -- 기존 HighestLevel 다시 표시
        if dungeonIcon.HighestLevel then
            dungeonIcon.HighestLevel:Show()
        end
    end

    if weeklyCountText then
        weeklyCountText:Hide()
    end
end

-- 모든 오버레이 표시
function MythicPlusHelper:ShowAllOverlays()
    for dungeonIcon, overlay in pairs(dungeonOverlays) do
        if overlay.nameText then overlay.nameText:Show() end
        if overlay.levelText then overlay.levelText:Show() end
        if overlay.scoreText then overlay.scoreText:Show() end
        if overlay.teleportButton then overlay.teleportButton:Show() end

        -- 기존 HighestLevel 숨기기
        if dungeonIcon.HighestLevel then
            dungeonIcon.HighestLevel:Hide()
        end
    end

    if weeklyCountText then
        weeklyCountText:Show()
    end

    self:UpdateAllDungeonOverlays()
end

-- 텍스트 크기 설정
function MythicPlusHelper:SetTextScale(scale)
    textScale = scale
    if self.db then
        self.db.scale = scale
    end

    -- 기본 폰트 크기에 스케일 적용
    local nameSize = math.floor(15 * scale)
    local levelSize = math.floor(30 * scale)
    local scoreSize = math.floor(15 * scale)

    for _, overlay in pairs(dungeonOverlays) do
        if overlay.nameText then
            overlay.nameText:SetFont(SL_FONT, nameSize, "OUTLINE")
        end
        if overlay.levelText then
            overlay.levelText:SetFont(SL_FONT, levelSize, "OUTLINE")
        end
        if overlay.scoreText then
            overlay.scoreText:SetFont(SL_FONT, scoreSize, "OUTLINE")
        end
    end

    if weeklyCountText then
        weeklyCountText:SetFont(SL_FONT, math.floor(18 * scale), "OUTLINE")
    end
end

-- 오버레이 표시 여부 반환
function MythicPlusHelper:IsOverlaysVisible()
    return overlaysVisible
end

-- ChallengesFrame 후킹
function MythicPlusHelper:HookChallengesFrame()
    if isHooked then return end

    -- Blizzard_ChallengesUI 로드 대기
    if not C_AddOns.IsAddOnLoaded("Blizzard_ChallengesUI") then
        local hookFrame = CreateFrame("Frame")
        hookFrame:RegisterEvent("ADDON_LOADED")
        hookFrame:SetScript("OnEvent", function(self, event, addon)
            if addon == "Blizzard_ChallengesUI" then
                C_Timer.After(0.1, function()
                    MythicPlusHelper:SetupChallengesFrame()
                end)
                self:UnregisterAllEvents()
            end
        end)
    else
        C_Timer.After(0.1, function()
            self:SetupChallengesFrame()
        end)
    end

    isHooked = true
end

-- ChallengesFrame 설정
function MythicPlusHelper:SetupChallengesFrame()
    if not ChallengesFrame then return end

    -- ChallengesFrame.Update 후킹
    if ChallengesFrame and type(ChallengesFrame.Update) == "function" then
        hooksecurefunc(ChallengesFrame, "Update", function()
            if not InCombatLockdown() then
                MythicPlusHelper:UpdateAllDungeonOverlays()
            end
        end)
    end

    -- ChallengesFrame OnShow 후킹
    ChallengesFrame:HookScript("OnShow", function()
        if isEnabled then
            C_Timer.After(0.1, function()
                MythicPlusHelper:UpdateAllDungeonOverlays()
                MythicPlusHelper:UpdateWeeklyCount()
            end)
        end
    end)

    -- 초기 설정
    self:UpdateAllDungeonOverlays()
    self:CreateWeeklyCountText()
end

-- 모든 던전 오버레이 업데이트
function MythicPlusHelper:UpdateAllDungeonOverlays()
    if InCombatLockdown() then return end
    if not ChallengesFrame then return end
    if not ChallengesFrame.DungeonIcons then return end

    for _, dungeonIcon in ipairs(ChallengesFrame.DungeonIcons) do
        self:CreateDungeonOverlay(dungeonIcon)
    end

    -- 오버레이 표시 여부에 따라 처리
    if not overlaysVisible then
        self:HideAllOverlays()
    end
end

-- 던전 오버레이 생성
function MythicPlusHelper:CreateDungeonOverlay(dungeonIcon)
    if not dungeonIcon or not dungeonIcon.mapID then return end

    local mapID = dungeonIcon.mapID

    -- 기존 HighestLevel 숨기기
    if dungeonIcon.HighestLevel then
        dungeonIcon.HighestLevel:Hide()
    end

    -- 오버레이가 이미 있으면 업데이트만
    if dungeonOverlays[dungeonIcon] then
        self:UpdateDungeonOverlay(dungeonIcon)
        return
    end

    local overlay = {}

    -- 폰트 크기 (스케일 적용)
    local nameSize = math.floor(15 * textScale)
    local levelSize = math.floor(30 * textScale)
    local scoreSize = math.floor(15 * textScale)

    -- 던전 이름 텍스트 (상단)
    overlay.nameText = dungeonIcon:CreateFontString(nil, "OVERLAY")
    overlay.nameText:SetFont(SL_FONT, nameSize, "OUTLINE")
    overlay.nameText:SetPoint("TOP", dungeonIcon, "TOP", 0, -2)
    overlay.nameText:SetTextColor(1, 1, 1, 1)

    -- 클리어 단수 텍스트 (중앙, 크게)
    overlay.levelText = dungeonIcon:CreateFontString(nil, "OVERLAY")
    overlay.levelText:SetFont(SL_FONT, levelSize, "OUTLINE")
    overlay.levelText:SetPoint("CENTER", dungeonIcon, "CENTER", 0, 0)
    overlay.levelText:SetTextColor(1, 1, 1, 1)

    -- 던전 점수 텍스트 (하단)
    overlay.scoreText = dungeonIcon:CreateFontString(nil, "OVERLAY")
    overlay.scoreText:SetFont(SL_FONT, scoreSize, "OUTLINE")
    overlay.scoreText:SetPoint("BOTTOM", dungeonIcon, "BOTTOM", 0, 2)
    overlay.scoreText:SetTextColor(1, 1, 1, 1)

    -- 텔레포트 버튼 (InsecureActionButtonTemplate 사용)
    local spellIDs = MAP_TO_SPELL[mapID]
    if spellIDs then
        local button = CreateFrame("Button", nil, dungeonIcon, "InsecureActionButtonTemplate")
        button:SetAllPoints(dungeonIcon)
        button:RegisterForClicks("AnyDown", "AnyUp")
        button:SetAttribute("type", "spell")
        button:SetAttribute("spell", nil)

        button:SetScript("OnEnter", function(self)
            MythicPlusHelper:UpdateTeleportButton(dungeonIcon, button, spellIDs, true)
        end)

        button:SetScript("OnLeave", function()
            -- 타이머 체인 중단
            if teleportUpdateTimer then
                teleportUpdateTimer:Cancel()
                teleportUpdateTimer = nil
            end
            if GameTooltip:IsOwned(dungeonIcon) then
                GameTooltip:Hide()
            end
        end)

        overlay.teleportButton = button
    end

    dungeonOverlays[dungeonIcon] = overlay

    -- 초기 업데이트
    self:UpdateDungeonOverlay(dungeonIcon)
end

-- 던전 오버레이 업데이트
function MythicPlusHelper:UpdateDungeonOverlay(dungeonIcon)
    local overlay = dungeonOverlays[dungeonIcon]
    if not overlay then return end

    local mapID = dungeonIcon.mapID
    if not mapID then return end

    -- 기존 HighestLevel 숨기기
    if dungeonIcon.HighestLevel then
        dungeonIcon.HighestLevel:Hide()
    end

    -- 던전 이름
    local dungeonName = MAP_NAMES[mapID]
    if dungeonName then
        overlay.nameText:SetText(dungeonName)
    else
        overlay.nameText:SetText("")
    end

    -- M+ 점수 및 단수 정보 가져오기
    local affixScores, bestOverAllScore = C_MythicPlus.GetSeasonBestAffixScoreInfoForMap(mapID)
    local intimeInfo, overtimeInfo = C_MythicPlus.GetSeasonBestForMap(mapID)

    local highLevel = 0
    local totalScore = 0
    local overTime = false

    if affixScores and #affixScores > 0 then
        highLevel = affixScores[1].level or 0
        overTime = affixScores[1].overTime or false
        totalScore = bestOverAllScore or 0
    elseif intimeInfo then
        highLevel = intimeInfo.level or 0
        overTime = false
        totalScore = bestOverAllScore or 0
    elseif overtimeInfo then
        highLevel = overtimeInfo.level or 0
        overTime = true
        totalScore = bestOverAllScore or 0
    end

    -- 단수 색상 결정
    local levelColor
    if totalScore >= 275 then
        levelColor = LEVEL_COLORS[4] -- orange
    elseif totalScore >= 226 then
        levelColor = LEVEL_COLORS[3] -- purple
    elseif totalScore >= 190 then
        levelColor = LEVEL_COLORS[2] -- blue
    elseif totalScore >= 126 then
        levelColor = LEVEL_COLORS[1] -- green
    else
        levelColor = LEVEL_COLORS[0] -- white
    end

    -- 단수 표시
    if highLevel > 0 then
        overlay.levelText:SetText(string.format("|c%s%d|r", levelColor, highLevel))
    else
        overlay.levelText:SetText("")
    end

    -- 점수 표시
    if totalScore and totalScore > 0 then
        overlay.scoreText:SetText(string.format("|c%s%d|r", levelColor, totalScore))
    else
        overlay.scoreText:SetText("")
    end
end

-- 텔레포트 버튼 업데이트
function MythicPlusHelper:UpdateTeleportButton(dungeonIcon, button, spellIDs, initialize)
    if WeakAuras and WeakAuras.InLoadingScreen and WeakAuras.InLoadingScreen() then return end
    if not initialize and not GameTooltip:IsOwned(dungeonIcon) then return end

    -- 기존 OnEnter 호출
    local parentOnEnter = dungeonIcon:GetScript("OnEnter")
    if parentOnEnter then
        parentOnEnter(dungeonIcon)
    end

    -- 최적의 텔레포트 스펠 찾기
    local teleportSpell = self:GetBestTeleportSpellInfo(spellIDs)

    if GameTooltip:NumLines() > 0 then
        GameTooltip:AddLine(" ")
    end

    if not teleportSpell then
        GameTooltip:AddLine("DDingToolKit")
        GameTooltip:AddLine(L["MYTHICPLUS_NO_TELEPORT_INFO"], 1, 0, 0)
    elseif teleportSpell.status == SpellStatus.NotLearned then
        GameTooltip:AddLine(teleportSpell.name)
        GameTooltip:AddLine(L["MYTHICPLUS_NOT_LEARNED"], 1, 0, 0)
    elseif teleportSpell.status == SpellStatus.OnCooldown then
        GameTooltip:AddLine(teleportSpell.name)
        GameTooltip:AddLine(teleportSpell.remainingTime, 1, 0, 0)
    elseif teleportSpell.status == SpellStatus.Ready then
        GameTooltip:AddLine(teleportSpell.name)
        GameTooltip:AddLine(L["MYTHICPLUS_AVAILABLE"], 0, 1, 0)
    end

    GameTooltip:Show()
    button:SetAttribute("spell", teleportSpell and teleportSpell.id)

    -- 기존 타이머 취소 후 새 타이머 시작
    if teleportUpdateTimer then
        teleportUpdateTimer:Cancel()
        teleportUpdateTimer = nil
    end

    -- 1초마다 업데이트 (GameTooltip 소유권 체크로 체인 중단)
    teleportUpdateTimer = C_Timer.NewTimer(1, function()
        teleportUpdateTimer = nil
        if GameTooltip:IsOwned(dungeonIcon) then
            self:UpdateTeleportButton(dungeonIcon, button, spellIDs)
        end
    end)
end

-- 최적의 텔레포트 스펠 정보 가져오기
function MythicPlusHelper:GetBestTeleportSpellInfo(spellIDs)
    if not spellIDs or #spellIDs == 0 then return nil end

    local teleportSpells = {}

    for spellIndex, spellID in ipairs(spellIDs) do
        table.insert(teleportSpells, self:GetTeleportSpellInfo(spellIndex, spellID))
    end

    table.sort(teleportSpells, function(a, b)
        if a.status == b.status then
            return a.index < b.index
        else
            return a.status < b.status
        end
    end)

    return teleportSpells[1]
end

-- 텔레포트 스펠 정보 가져오기
function MythicPlusHelper:GetTeleportSpellInfo(spellIndex, spellID)
    local spell = C_Spell.GetSpellInfo(spellID)
    local isSpellKnown = (IsPlayerSpell and IsPlayerSpell(spellID)) or (IsSpellKnown and IsSpellKnown(spellID)) or false
    local cooldown = C_Spell.GetSpellCooldown(spellID)

    -- GCD 체크
    local gcdDuration = 0
    if WeakAuras and WeakAuras.gcdDuration then
        gcdDuration = WeakAuras.gcdDuration()
    end

    local isOnCooldown = cooldown and cooldown.duration ~= 0 and cooldown.duration ~= gcdDuration or false
    local remainingTime = nil

    if isOnCooldown and cooldown then
        local remaining = math.ceil(cooldown.startTime + cooldown.duration - GetTime())
        remainingTime = SecondsToTime(remaining)
    end

    local status
    if not spell or not isSpellKnown or not cooldown then
        status = SpellStatus.NotLearned
    elseif isOnCooldown then
        status = SpellStatus.OnCooldown
    else
        status = SpellStatus.Ready
    end

    return {
        index = spellIndex,
        id = spellID,
        status = status,
        name = spell and spell.name or "던전 텔레포트",
        remainingTime = remainingTime,
    }
end

-- 이번주 쐐기 횟수 텍스트 생성
function MythicPlusHelper:CreateWeeklyCountText()
    if weeklyCountText then return end
    if not ChallengesFrame then return end

    local fontSize = math.floor(18 * textScale)
    weeklyCountText = ChallengesFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    weeklyCountText:SetFont(SL_FONT, fontSize, "OUTLINE")
    weeklyCountText:SetPoint("BOTTOMRIGHT", ChallengesFrame, "BOTTOMRIGHT", -10, -20)

    self:UpdateWeeklyCount()

    -- 오버레이가 비활성화된 상태면 숨기기
    if not overlaysVisible then
        weeklyCountText:Hide()
    end
end

-- 이번주 쐐기 횟수 업데이트
function MythicPlusHelper:UpdateWeeklyCount()
    if not weeklyCountText then return end

    local runHistory = C_MythicPlus.GetRunHistory(false, true)
    local count = runHistory and #runHistory or 0

    weeklyCountText:SetText(string.format(L["MYTHICPLUS_WEEKLY_COUNT"], count))
end

-- Toggle 함수 (슬래시 커맨드용 - PVE 창 열기)
function MythicPlusHelper:Toggle()
    if not PVEFrame then
        PVEFrame_ToggleFrame("ChallengesFrame")
    elseif PVEFrame:IsShown() and PVEFrame.activeTabIndex == 4 then
        HideUIPanel(PVEFrame)
    else
        PVEFrame_ToggleFrame("ChallengesFrame")
    end
end

-- 메인 프레임 반환
function MythicPlusHelper:GetMainFrame()
    return ChallengesFrame
end

-- 이벤트 프레임
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
eventFrame:RegisterEvent("MYTHIC_PLUS_NEW_WEEKLY_RECORD")
eventFrame:RegisterEvent("MYTHIC_PLUS_CURRENT_AFFIX_UPDATE")
eventFrame:RegisterEvent("WEEKLY_REWARDS_UPDATE")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        if isEnabled and C_AddOns.IsAddOnLoaded("Blizzard_ChallengesUI") then
            C_Timer.After(0.5, function()
                MythicPlusHelper:SetupChallengesFrame()
            end)
        end
    elseif event == "CHALLENGE_MODE_COMPLETED" or event == "MYTHIC_PLUS_NEW_WEEKLY_RECORD" then
        if isEnabled then
            C_Timer.After(1, function()
                MythicPlusHelper:UpdateAllDungeonOverlays()
                MythicPlusHelper:UpdateWeeklyCount()
            end)
        end
    elseif event == "WEEKLY_REWARDS_UPDATE" or event == "MYTHIC_PLUS_CURRENT_AFFIX_UPDATE" then
        if isEnabled then
            MythicPlusHelper:UpdateWeeklyCount()
        end
    end
end)

-- 모듈 등록
DDingToolKit:RegisterModule("MythicPlusHelper", MythicPlusHelper)
