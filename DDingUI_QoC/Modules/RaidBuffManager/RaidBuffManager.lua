--[[
    DDingQoC - RaidBuffManager Module
    공격대 버프 추적 + 클릭 시전 + 거리 글로우 + 누락 명단 표시
    RaidBuffManager Enhanced 포팅 (12.0 Secret Value / Taint 보강)
]]

local addonName, ns = ...
local DDingQoC = ns.DDingQoC
local L = ns.L
local SL = _G.DDingUI_StyleLib
local SL_FONT = (SL and SL.Font and SL.Font.path) or "Fonts\\2002.TTF"
local SL_FLAT = (SL and SL.Textures and SL.Textures.flat) or "Interface\\Buttons\\WHITE8x8"
local CHAT_PREFIX = (SL and SL.GetChatPrefix) and SL.GetChatPrefix("QoC", "QoC") or "|cffffffffDDing|r|cffffa300UI|r |cffd93380QoC|r: "

------------------------------------------------------------
-- Module table
------------------------------------------------------------
local RBM = {}
RBM.name = "RaidBuffManager"
ns.RaidBuffManager = RBM

------------------------------------------------------------
-- 12.0 Secret Value 안전 함수
------------------------------------------------------------
local function safeString(val)
    if issecretvalue and issecretvalue(val) then return nil end
    if type(val) ~= "string" then return nil end
    return val
end

local function safeNumber(val)
    if issecretvalue and issecretvalue(val) then return nil end
    if type(val) ~= "number" then return nil end
    return val
end

------------------------------------------------------------
-- 음식 버프 이름 (다국어)
------------------------------------------------------------
local FoodBuffNames = {
    ["Well Fed"] = true, ["Hearty Well Fed"] = true,
    ["충분한 포만감"] = true, ["포만감"] = true,
    ["充分進食"] = true, ["进食充分"] = true,
    ["Сытость"] = true, ["Satt"] = true, ["Bien nourri"] = true,
    ["Bien alimentado"] = true, ["Bem Alimentado"] = true, ["Ben Nutrito"] = true,
}

-- C_Spell 기반 동적 이름 추가
local wellFedName = C_Spell.GetSpellName and C_Spell.GetSpellName(19705)
if wellFedName then FoodBuffNames[wellFedName] = true end
local heartyName = C_Spell.GetSpellName and C_Spell.GetSpellName(462187)
if heartyName then FoodBuffNames[heartyName] = true end

------------------------------------------------------------
-- 버프 데이터
------------------------------------------------------------
local BuffData = {
    { id = "AP",      spellIDs = {6673, 264761},  icon = 132333, nameSpell = 6673,
      providers = {["WARRIOR"] = true},
      ignore = {["PRIEST"]=true, ["MAGE"]=true, ["WARLOCK"]=true, ["EVOKER"]=true},
      ignoreRole = {["HEALER"]=true} },

    { id = "SP",      spellIDs = {1459, 264760},  icon = 135932, nameSpell = 1459,
      providers = {["MAGE"] = true},
      ignore = {["WARRIOR"]=true, ["ROGUE"]=true, ["HUNTER"]=true, ["DEATHKNIGHT"]=true, ["DEMONHUNTER"]=true},
      ignoreRole = {["TANK"]=true} },

    { id = "STA",     spellIDs = {21562, 264764}, icon = 135987, nameSpell = 21562,
      providers = {["PRIEST"] = true}, ignore = {} },

    { id = "MOTW",    spellIDs = {1126},          icon = 136078, nameSpell = 1126,
      providers = {["DRUID"] = true}, ignore = {} },

    { id = "BRONZE",  spellIDs = {364342},        icon = 4622448, nameSpell = 364342,
      providers = {["EVOKER"] = true}, ignore = {} },

    { id = "SKYFURY", spellIDs = {462854},        icon = 4630367, nameSpell = 462854,
      providers = {["SHAMAN"] = true}, ignore = {} },

    { id = "FOOD",    spellIDs = {},              icon = 136000, nameSpell = 19705,
      providers = nil, ignore = {}, isFood = true },
}

-- 현지화 이름 초기화
for _, data in ipairs(BuffData) do
    local spellInfo = data.nameSpell and C_Spell.GetSpellInfo(data.nameSpell)
    data.localizedName = spellInfo and spellInfo.name or data.id
    data.spellName = spellInfo and spellInfo.name
end

------------------------------------------------------------
-- 로컬 변수
------------------------------------------------------------
local mainFrame = nil
local buttons = {}
local isEnabled = false
local ticker = nil

------------------------------------------------------------
-- 글로우 효과
------------------------------------------------------------
local function ShowGlow(btn)
    if not btn._glow then
        btn._glow = CreateFrame("Frame", nil, btn)
        btn._glow:SetFrameLevel(btn:GetFrameLevel() + 1)
        btn._glow:SetPoint("CENTER")
        btn._glow:SetSize(btn:GetWidth() * 1.4, btn:GetHeight() * 1.4)
        local tex = btn._glow:CreateTexture(nil, "OVERLAY")
        tex:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
        tex:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
        tex:SetAllPoints()
        tex:SetBlendMode("ADD")
        local anim = btn._glow:CreateAnimationGroup()
        anim:SetLooping("BOUNCE")
        local fade = anim:CreateAnimation("Alpha")
        fade:SetFromAlpha(1); fade:SetToAlpha(0.2); fade:SetDuration(0.5)
        btn._glow._anim = anim
    end
    btn._glow:Show()
    if not btn._glow._anim:IsPlaying() then btn._glow._anim:Play() end
end

local function HideGlow(btn)
    if btn._glow then btn._glow._anim:Stop(); btn._glow:Hide() end
end

------------------------------------------------------------
-- 안전한 버프 검색 (12.0 Secret Value 보강)
------------------------------------------------------------
local function HasRequiredBuff(unit, data)
    local i = 1
    while true do
        local ok, aura = pcall(C_UnitAuras.GetBuffDataByIndex, unit, i)
        if not ok or not aura then break end

        if data.isFood then
            local auraName = safeString(aura.name)
            if auraName and FoodBuffNames[auraName] then
                return true
            end
        else
            local auraSpellId = safeNumber(aura.spellId)
            if auraSpellId then
                for _, id in ipairs(data.spellIDs) do
                    if auraSpellId == id then return true end
                end
            end
            local auraName = safeString(aura.name)
            if auraName and auraName == data.localizedName then
                return true
            end
        end
        i = i + 1
    end
    return false
end

------------------------------------------------------------
-- 버튼 생성
------------------------------------------------------------
local function CreateButtons()
    if #buttons > 0 then return end
    if not mainFrame then return end
    local db = RBM.db
    if not db then return end
    local btnSize = db.iconSize or 36

    for i, data in ipairs(BuffData) do
        local btnTemplate = data.isFood and nil or "SecureActionButtonTemplate"
        local btn = CreateFrame("Button", "DDingQoC_RBM_" .. data.id, mainFrame, btnTemplate)
        btn:SetSize(btnSize, btnSize)
        btn:Hide()

        -- 클릭 시전 (전투 중 SecureAction 보호)
        if not data.isFood and data.spellName then
            btn:RegisterForClicks("AnyUp", "AnyDown")
            btn:SetAttribute("type", "spell")
            btn:SetAttribute("spell", data.spellName)
            btn:SetAttribute("unit", "player")
        end

        -- 아이콘
        btn._icon = btn:CreateTexture(nil, "BACKGROUND")
        btn._icon:SetAllPoints()
        btn._icon:SetTexture(data.icon)
        btn._icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        -- 테두리
        local border = CreateFrame("Frame", nil, btn, "BackdropTemplate")
        border:SetAllPoints()
        border:SetBackdrop({ edgeFile = SL_FLAT, edgeSize = 1 })
        border:SetBackdropBorderColor(0, 0, 0, 1)
        border:SetFrameLevel(btn:GetFrameLevel() + 2)

        -- 카운트 텍스트
        btn._text = btn:CreateFontString(nil, "OVERLAY")
        btn._text:SetFont(db.font or SL_FONT, db.fontSize or 12, "OUTLINE")
        btn._text:SetPoint("BOTTOM", btn, "BOTTOM", 0, -14)

        -- 툴팁
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(data.localizedName, 1, 0.82, 0)
            if self._missingNames and #self._missingNames > 0 then
                GameTooltip:AddLine(L["RAIDBUFF_MISSING"] or "누락:", 1, 0, 0)
                for _, name in ipairs(self._missingNames) do
                    GameTooltip:AddLine(name, 1, 1, 1)
                end
            else
                GameTooltip:AddLine(L["RAIDBUFF_ALL_GOOD"] or "모두 버프됨!", 0, 1, 0)
            end
            if data.isMine then
                GameTooltip:AddLine("\n" .. (L["RAIDBUFF_CLICK_CAST"] or "<좌클릭하여 시전>"), 0, 1, 1)
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        btn._data = data
        buttons[i] = btn
    end
end

------------------------------------------------------------
-- 핵심 스캔 엔진
------------------------------------------------------------
local function UpdateBuffs()
    if InCombatLockdown() then return end
    if not isEnabled or not mainFrame then return end

    local db = RBM.db
    if not db then return end

    -- 유닛 목록 구성
    local units = {}
    if IsInRaid() then
        for j = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. j end
    elseif IsInGroup() then
        units[#units + 1] = "player"
        for j = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. j end
    else
        units[#units + 1] = "player"
    end

    -- 그룹 내 직업 파악
    local presentClasses = {}
    for _, unit in ipairs(units) do
        if UnitExists(unit) and UnitIsConnected(unit) then
            local _, classFile = UnitClass(unit)
            if classFile then presentClasses[classFile] = true end
        end
    end

    local visibleCount = 0
    local btnSize = db.iconSize or 36
    local dir = db.growDirection or "RIGHT"

    for _, btn in ipairs(buttons) do
        local data = btn._data

        -- 내가 시전 가능한지
        if not data.isFood and data.spellIDs and data.spellIDs[1] then
            data.isMine = IsPlayerSpell(data.spellIDs[1])
        end

        local count, needs = 0, 0
        local missingNames = {}
        local glowRange = false

        -- 추적 모드 체크
        local shouldTrack = true
        if db.trackMode == 2 then
            shouldTrack = data.isMine
        elseif db.trackMode == 3 then
            shouldTrack = db.customTrack and db.customTrack[data.id] ~= false
        end

        -- 제공자 존재 여부
        local hasProvider = false
        if shouldTrack then
            if data.providers == nil then
                hasProvider = true -- 음식은 항상
            else
                for pClass in pairs(data.providers) do
                    if presentClasses[pClass] then hasProvider = true; break end
                end
            end
        end

        if hasProvider and shouldTrack then
            for _, unit in ipairs(units) do
                if UnitExists(unit) and not UnitIsDeadOrGhost(unit) and UnitIsConnected(unit) then
                    local _, classFile = UnitClass(unit)
                    local role = UnitGroupRolesAssigned(unit)

                    if role == "NONE" and unit == "player" then
                        local spec = GetSpecialization()
                        if spec then role = GetSpecializationRole(spec) end
                    end

                    local shouldIgnore = (data.ignore and data.ignore[classFile])
                        or (data.ignoreRole and data.ignoreRole[role])

                    if not shouldIgnore then
                        needs = needs + 1
                        if HasRequiredBuff(unit, data) then
                            count = count + 1
                        else
                            local name = UnitName(unit)
                            local colorStr = RAID_CLASS_COLORS[classFile] and RAID_CLASS_COLORS[classFile].colorStr or "ffffffff"
                            missingNames[#missingNames + 1] = "|c" .. colorStr .. (name or "?") .. "|r"

                            -- 거리 글로우
                            if not data.isFood then
                                if unit == "player" then
                                    glowRange = true
                                elseif data.isMine and data.spellName then
                                    local ok, inRange = pcall(C_Spell.IsSpellInRange, data.spellName, unit)
                                    if ok then
                                        if inRange == true or inRange == 1 then
                                            glowRange = true
                                        elseif inRange == nil and UnitIsVisible(unit) then
                                            glowRange = true
                                        end
                                    end
                                elseif not data.isMine and UnitIsVisible(unit) then
                                    glowRange = true
                                end
                            end
                        end
                    end
                end
            end
        end

        btn._missingNames = missingNames

        if needs > 0 and count < needs then
            btn:SetSize(btnSize, btnSize)
            btn._text:SetText(count .. "/" .. needs)
            btn:Show()

            -- 위치 계산
            local xOfs, yOfs = 0, 0
            local gap = btnSize + 4
            if dir == "RIGHT" then     xOfs = visibleCount * gap
            elseif dir == "LEFT" then  xOfs = -visibleCount * gap
            elseif dir == "UP" then    yOfs = visibleCount * gap
            elseif dir == "DOWN" then  yOfs = -visibleCount * gap end

            btn:ClearAllPoints()
            btn:SetPoint("CENTER", mainFrame, "CENTER", xOfs, yOfs)
            visibleCount = visibleCount + 1

            -- 글로우
            if data.isMine and glowRange then
                ShowGlow(btn)
                btn._icon:SetDesaturated(false)
                btn._icon:SetVertexColor(1, 1, 1)
                btn:SetAlpha(1)
            else
                HideGlow(btn)
                btn._icon:SetDesaturated(true)
                btn._icon:SetVertexColor(1, 0.4, 0.4)
                btn:SetAlpha(0.7)
            end
        else
            btn:Hide()
            HideGlow(btn)
        end
    end
end

------------------------------------------------------------
-- 프레임 생성
------------------------------------------------------------
local function CreateMainFrame()
    if mainFrame then return end
    local db = RBM.db
    if not db then return end

    mainFrame = CreateFrame("Frame", "DDingQoC_RBMFrame", UIParent)
    mainFrame:SetFrameStrata("HIGH")
    mainFrame:SetFrameLevel(100)
    mainFrame:SetSize(120, 50)
    mainFrame:SetClampedToScreen(true)

    local pos = db.position
    if pos then
        mainFrame:SetPoint(pos.point or "CENTER", UIParent, pos.relativePoint or "CENTER", pos.x or 0, pos.y or -150)
    else
        mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
    end

    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScale(db.scale or 1.0)

    -- 드래그 영역 배경 (잠금 해제 시)
    mainFrame._bg = mainFrame:CreateTexture(nil, "BACKGROUND")
    mainFrame._bg:SetAllPoints()
    mainFrame._bg:SetColorTexture(0, 1, 0, 0.4)

    mainFrame._dragText = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mainFrame._dragText:SetPoint("CENTER")
    mainFrame._dragText:SetText(L["RAIDBUFF_DRAG"] or "RBM 드래그")

    mainFrame:SetScript("OnDragStart", function(self)
        if not RBM.db.locked then self:StartMoving() end
    end)
    mainFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        RBM.db.position = { point = point, relativePoint = relPoint, x = x, y = y }
    end)

    -- 잠금 상태 반영
    RBM:UpdateLock()

    -- 전투 중 숨김
    RegisterStateDriver(mainFrame, "visibility", "[combat] hide; show")
end

------------------------------------------------------------
-- 모듈 라이프사이클
-- Core.lua에서 modules.RaidBuffManager ~= false일 때만 호출됨
-- 따라서 여기서 별도 enabled 체크 불필요
------------------------------------------------------------
function RBM:OnInitialize()
    -- DB 참조 확보
    if ns.db and ns.db.profile and ns.db.profile.RaidBuffManager then
        self.db = ns.db.profile.RaidBuffManager
    end
end

function RBM:OnEnable()
    -- DB 참조 안전 확보
    if not self.db then
        if ns.db and ns.db.profile and ns.db.profile.RaidBuffManager then
            self.db = ns.db.profile.RaidBuffManager
        else
            return
        end
    end

    -- Core.lua가 modules.RaidBuffManager를 체크해서 호출하므로, 바로 활성화
    isEnabled = true
    CreateMainFrame()
    CreateButtons()
    self:UpdateLock()

    -- 1초 간격 스캔
    if not ticker then
        ticker = C_Timer.NewTicker(1.0, UpdateBuffs)
    end

    -- 즉시 1회 스캔
    C_Timer.After(0.5, UpdateBuffs)
end

function RBM:OnDisable()
    isEnabled = false
    if ticker then ticker:Cancel(); ticker = nil end
    if mainFrame then mainFrame:Hide() end
end

------------------------------------------------------------
-- 설정 업데이트
------------------------------------------------------------
function RBM:UpdateLock()
    if not mainFrame then return end
    if not self.db then return end
    if self.db.locked then
        mainFrame:EnableMouse(false)
        mainFrame._bg:Hide()
        mainFrame._dragText:Hide()
    else
        mainFrame:EnableMouse(true)
        mainFrame._bg:Show()
        mainFrame._dragText:Show()
    end
end

function RBM:UpdateScale()
    if mainFrame and self.db then
        mainFrame:SetScale(self.db.scale or 1.0)
    end
end

function RBM:UpdateStyle()
    if not mainFrame or not self.db then return end
    local db = self.db
    local btnSize = db.iconSize or 36
    for _, btn in ipairs(buttons) do
        btn:SetSize(btnSize, btnSize)
        btn._text:SetFont(db.font or SL_FONT, db.fontSize or 12, "OUTLINE")
    end
    UpdateBuffs()
end

function RBM:ResetPosition()
    if mainFrame then
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
        if self.db then
            self.db.position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -150 }
        end
        print(CHAT_PREFIX .. (L["POSITION_RESET"] or "위치가 초기화되었습니다."))
    end
end

function RBM:TestMode()
    -- DB 확보
    if not self.db then
        if ns.db and ns.db.profile and ns.db.profile.RaidBuffManager then
            self.db = ns.db.profile.RaidBuffManager
        else
            print(CHAT_PREFIX .. "|cFFFF0000DB를 찾을 수 없습니다.|r")
            return
        end
    end

    -- 프레임 생성
    if not mainFrame then
        CreateMainFrame()
        CreateButtons()
    end

    -- 토글
    if mainFrame:IsShown() then
        mainFrame:Hide()
        isEnabled = false
        if ticker then ticker:Cancel(); ticker = nil end
        print(CHAT_PREFIX .. "RaidBuffManager " .. (L["TEST_MODE"] or "테스트") .. " OFF")
    else
        mainFrame:Show()
        isEnabled = true
        self:UpdateLock()

        -- 티커 시작
        if not ticker then
            ticker = C_Timer.NewTicker(1.0, UpdateBuffs)
        end

        -- 즉시 스캔
        UpdateBuffs()
        print(CHAT_PREFIX .. "RaidBuffManager " .. (L["TEST_MODE"] or "테스트") .. " ON")
    end
end

------------------------------------------------------------
-- 모듈 등록
------------------------------------------------------------
DDingQoC:RegisterModule("RaidBuffManager", RBM)
