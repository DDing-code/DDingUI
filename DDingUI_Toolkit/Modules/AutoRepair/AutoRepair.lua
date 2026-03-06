--[[
    DDingToolKit - AutoRepair Module
    상인 방문 시 장비 자동 수리
]]

local addonName, ns = ...
local DDingToolKit = ns.DDingToolKit
local L = ns.L
local SL = _G.DDingUI_StyleLib -- [STYLE]
local CHAT_PREFIX = (SL and SL.GetChatPrefix) and SL.GetChatPrefix("MJToolkit", "Toolkit") or "|cffffffffDDing|r|cffffa300UI|r |cff33bfe6Toolkit|r: " -- [STYLE]

-- AutoRepair 모듈
local AutoRepair = {}
ns.AutoRepair = AutoRepair

-- 로컬 변수
local eventFrame = nil

-- 초기화
function AutoRepair:OnInitialize()
    self.db = ns.db.profile.AutoRepair
    if not self.db then
        self.db = {}
        ns.db.profile.AutoRepair = self.db
    end
end

-- 활성화
function AutoRepair:OnEnable()
    self:RegisterEvents()
end

-- 비활성화
function AutoRepair:OnDisable()
    if eventFrame then
        eventFrame:UnregisterAllEvents()
    end
end

-- 이벤트 등록
function AutoRepair:RegisterEvents()
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
    end

    eventFrame:RegisterEvent("MERCHANT_SHOW")

    eventFrame:SetScript("OnEvent", function(f, event)
        if event == "MERCHANT_SHOW" then
            self:DoRepair()
        end
    end)
end

-- 수리 실행
function AutoRepair:DoRepair()
    -- 수리 가능 상인인지 확인
    if not CanMerchantRepair() then return end

    -- 수리 비용 확인
    local cost, canRepair = GetRepairAllCost()
    if not canRepair or cost <= 0 then return end

    local usedGuildBank = false

    -- 길드 금고 수리 시도
    if self.db.useGuildBank then
        if IsInGuild() and CanGuildBankRepair() then
            RepairAllItems(true)
            usedGuildBank = true
        else
            -- 길드 금고 사용 불가 → 개인 골드로 수리
            RepairAllItems(false)
        end
    else
        -- 개인 골드로 수리
        RepairAllItems(false)
    end

    -- 채팅 출력
    if self.db.chatOutput then
        local costText = GetCoinTextureString(cost)
        local source
        if usedGuildBank then
            source = L["AUTOREPAIR_GUILD_BANK"]
        else
            source = L["AUTOREPAIR_PERSONAL_GOLD"]
        end
        print(string.format("%s%s: %s (%s)", CHAT_PREFIX, L["AUTOREPAIR_REPAIRED"], costText, source)) -- [STYLE]
    end
end

-- 모듈 등록
DDingToolKit:RegisterModule("AutoRepair", AutoRepair)
