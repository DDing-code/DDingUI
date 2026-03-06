--[[
    DDingToolKit - CastingAlert Module
    타겟 스펠 알림 (asCastingAlert 참고)
    레이아웃: [아이콘] [남은초] [아이콘] - 위로 쌓임
]]

local addonName, ns = ...
local DDingToolKit = ns.DDingToolKit
local UI = ns.UI
local L = ns.L
local SL = _G.DDingUI_StyleLib -- [12.0.1]
local SL_FLAT = (SL and SL.Textures and SL.Textures.flat) or "Interface\\Buttons\\WHITE8x8" -- [12.0.1]
local CHAT_PREFIX = (SL and SL.GetChatPrefix) and SL.GetChatPrefix("QoC", "QoC") or "|cffffffffDDing|r|cffffa300UI|r |cffd93380QoC|r: " -- [STYLE]

local CastingAlert = {}
CastingAlert.name = "CastingAlert"
ns.CastingAlert = CastingAlert

-- 탱커 역할 체크
local function IsPlayerTank()
    local spec = GetSpecialization()
    if spec then
        local role = GetSpecializationRole(spec)
        return role == "TANK"
    end
    return false
end

-- 로컬 변수
local mainFrame = nil
local castFrames = {}
local castingUnits = {}
local updateTicker = nil
local isEnabled = false
local isTestMode = false
local prevTargetingCount = 0

-- 우선순위 비교 (타겟 > 높은레벨 > 낮은레벨)
local function comparator(a, b)
    return a.level > b.level
end

-- 12.0 Secret value 헬퍼
local function NotSecretValue(val)
    return ns.NotSecretValue(val)
end

-- 시전 체크 (UnitIsUnit 타겟 필터 제거 - secret value이므로 ShowCastings에서 SetAlphaFromBoolean으로 처리)
local function CheckCasting(unit)
    local name, _, texture, startTime, endTime, _, _, notInterruptible, spellId = UnitCastingInfo(unit)
    local duration = nil
    local isChannel = false

    if not name then
        name, _, texture, startTime, endTime, _, notInterruptible, spellId = UnitChannelInfo(unit)
        if name then
            duration = UnitChannelDuration(unit)
            isChannel = true
        end
    else
        duration = UnitCastingDuration(unit)
    end

    if name and duration then
        local level = UnitLevel(unit)
        if NotSecretValue(level) then
            if level < 0 then level = 1000 end
        else
            level = 999
        end

        return true, {
            level = level,
            duration = duration,
            texture = texture,
            spellId = spellId,
            isChannel = isChannel,
            notInterruptible = notInterruptible,
        }
    end

    return false
end

-- 초기화
function CastingAlert:OnInitialize()
    self.db = ns.db.profile.CastingAlert
    if not self.db then
        self.db = {}
        ns.db.profile.CastingAlert = self.db
    end
end

-- 활성화
function CastingAlert:OnEnable()
    if not self.db then
        if ns.db and ns.db.profile and ns.db.profile.CastingAlert then
            self.db = ns.db.profile.CastingAlert
        else
            return
        end
    end

    if not self.db.enabled then
        isEnabled = false
        return
    end

    -- 탱커 전문화 비활성화 체크
    if self.db.disableForTank and IsPlayerTank() then
        isEnabled = false
        self:RegisterSpecChange()
        return
    end

    isEnabled = true
    self:CreateMainFrame()
    self:StartUpdate()

    -- disableForTank 옵션이 켜져 있으면 전문화 변경 감시
    if self.db.disableForTank then
        self:RegisterSpecChange()
    end
end

-- 전문화 변경 이벤트 등록
function CastingAlert:RegisterSpecChange()
    if self._specFrame then return end
    self._specFrame = CreateFrame("Frame")
    self._specFrame:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_SPECIALIZATION_CHANGED" and (not unit or unit == "player") then
            CastingAlert:OnSpecChanged()
        end
    end)
    self._specFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
end

-- 전문화 변경 시 탱커 체크
function CastingAlert:OnSpecChanged()
    if not self.db or not self.db.enabled or not self.db.disableForTank then return end

    if IsPlayerTank() then
        -- 탱커로 전환 → 비활성화
        if isEnabled then
            self:OnDisable()
        end
    else
        -- 비탱커로 전환 → 재활성화
        if not isEnabled then
            isEnabled = true
            self:CreateMainFrame()
            self:StartUpdate()
        end
    end
end

-- 비활성화
function CastingAlert:OnDisable()
    isEnabled = false
    if updateTicker then
        updateTicker:Cancel()
        updateTicker = nil
    end
    if mainFrame then
        mainFrame:Hide()
        if mainFrame.eventFrame then
            mainFrame.eventFrame:UnregisterAllEvents()
        end
    end
    wipe(castingUnits)
end

-- 메인 프레임 생성
function CastingAlert:CreateMainFrame()
    if mainFrame then return end

    local pos = self.db.position or {}
    local frame = CreateFrame("Frame", "DDingToolKit_CastingAlertFrame", UIParent)
    frame:SetSize(1, 1)
    frame:SetPoint(pos.point or "CENTER", UIParent, pos.relativePoint or "CENTER", pos.x or 0, pos.y or -30)
    frame:SetFrameStrata("LOW")
    frame:SetScale(self.db.scale or 1.0)
    frame:EnableMouse(false)

    -- 드래그 (테스트 모드에서만)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if isTestMode then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint()
        CastingAlert.db.position.point = point
        CastingAlert.db.position.relativePoint = relativePoint
        CastingAlert.db.position.x = x
        CastingAlert.db.position.y = y
    end)

    mainFrame = frame
    self:CreateCastFrames()
end

-- 한 줄 프레임 생성: [아이콘] [초] [아이콘]
function CastingAlert:CreateCastFrames()
    local maxShow = self.db.maxShow or 10
    local size = self.db.iconSize or 35
    local fontSize = self.db.fontSize or 18
    local textWidth = fontSize * 3  -- 초 텍스트 영역 너비
    local rowWidth = size + 4 + textWidth + 4 + size

    for i = 1, maxShow do
        local row = CreateFrame("Frame", nil, mainFrame)
        row:SetSize(rowWidth, size)
        row:SetPoint("CENTER", mainFrame, "CENTER", 0, 0)
        row:SetFrameLevel(1000 - i)
        row:EnableMouse(false)

        -- 왼쪽 아이콘
        row.leftIcon = CreateFrame("Frame", nil, row, "BackdropTemplate")
        row.leftIcon:SetSize(size, size)
        row.leftIcon:SetPoint("LEFT", row, "LEFT", 0, 0)

        row.leftIcon.border = row.leftIcon:CreateTexture(nil, "BACKGROUND")
        row.leftIcon.border:SetAllPoints()
        row.leftIcon.border:SetTexture(SL_FLAT) -- [12.0.1]
        row.leftIcon.border:SetVertexColor(0, 0, 0)

        row.leftIcon.tex = row.leftIcon:CreateTexture(nil, "ARTWORK")
        row.leftIcon.tex:SetAllPoints()
        row.leftIcon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        row.leftIcon.important = row.leftIcon:CreateTexture(nil, "OVERLAY")
        row.leftIcon.important:SetAllPoints()
        row.leftIcon.important:SetTexture(SL_FLAT) -- [12.0.1]
        row.leftIcon.important:SetTexCoord(0.08, 0.08, 0.08, 0.92, 0.92, 0.08, 0.92, 0.92)
        row.leftIcon.important:SetVertexColor(1, 0.82, 0)
        row.leftIcon.important:SetAlpha(0)

        row.leftIcon.cooldown = CreateFrame("Cooldown", nil, row.leftIcon, "CooldownFrameTemplate")
        row.leftIcon.cooldown:SetAllPoints()
        row.leftIcon.cooldown:SetReverse(true)
        row.leftIcon.cooldown:SetDrawEdge(true)
        row.leftIcon.cooldown:SetDrawSwipe(true)
        row.leftIcon.cooldown:SetHideCountdownNumbers(true)

        -- 가운데 초 텍스트
        row.timeText = row:CreateFontString(nil, "OVERLAY")
        row.timeText:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")
        row.timeText:SetPoint("CENTER", row, "CENTER", 0, 0)
        row.timeText:SetTextColor(1, 0.82, 0)
        row.timeText:SetJustifyH("CENTER")

        -- 오른쪽 아이콘
        row.rightIcon = CreateFrame("Frame", nil, row, "BackdropTemplate")
        row.rightIcon:SetSize(size, size)
        row.rightIcon:SetPoint("RIGHT", row, "RIGHT", 0, 0)

        row.rightIcon.border = row.rightIcon:CreateTexture(nil, "BACKGROUND")
        row.rightIcon.border:SetAllPoints()
        row.rightIcon.border:SetTexture(SL_FLAT) -- [12.0.1]
        row.rightIcon.border:SetVertexColor(0, 0, 0)

        row.rightIcon.tex = row.rightIcon:CreateTexture(nil, "ARTWORK")
        row.rightIcon.tex:SetAllPoints()
        row.rightIcon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        row.rightIcon.important = row.rightIcon:CreateTexture(nil, "OVERLAY")
        row.rightIcon.important:SetAllPoints()
        row.rightIcon.important:SetTexture(SL_FLAT) -- [12.0.1]
        row.rightIcon.important:SetTexCoord(0.08, 0.08, 0.08, 0.92, 0.92, 0.08, 0.92, 0.92)
        row.rightIcon.important:SetVertexColor(1, 0.82, 0)
        row.rightIcon.important:SetAlpha(0)

        row.rightIcon.cooldown = CreateFrame("Cooldown", nil, row.rightIcon, "CooldownFrameTemplate")
        row.rightIcon.cooldown:SetAllPoints()
        row.rightIcon.cooldown:SetReverse(true)
        row.rightIcon.cooldown:SetDrawEdge(true)
        row.rightIcon.cooldown:SetDrawSwipe(true)
        row.rightIcon.cooldown:SetHideCountdownNumbers(true)

        row:SetAlpha(0)
        row:Show()

        castFrames[i] = row
    end
end

-- 시전 표시 업데이트
function CastingAlert:ShowCastings()
    -- 정렬된 결과 수집 (UnitIsUnit 사전필터 제거 - secret value)
    local sorted = {}
    for unit, info in pairs(castingUnits) do
        if info then
            info.unit = unit
            table.insert(sorted, info)
        end
    end
    table.sort(sorted, comparator)

    local maxShow = self.db.maxShow or 10
    local size = self.db.iconSize or 35
    local rowSpacing = size + 4
    local currShow = 0
    local onlyMe = self.db.onlyTargetingMe
    local dimAlpha = self.db.dimAlpha or 0.4
    local targetingCount = 0

    for i, castInfo in ipairs(sorted) do
        if i > maxShow then break end

        local row = castFrames[i]
        if row then
            -- 위치: 첫 번째는 0, 두 번째부터 위로 쌓임
            row:ClearAllPoints()
            row:SetPoint("CENTER", mainFrame, "CENTER", 0, (i - 1) * rowSpacing)

            -- 양쪽 아이콘에 같은 텍스처
            row.leftIcon.tex:SetTexture(castInfo.texture)
            row.rightIcon.tex:SetTexture(castInfo.texture)

            -- 쿨다운 swipe
            row.leftIcon.cooldown:SetCooldownFromDurationObject(castInfo.duration)
            row.rightIcon.cooldown:SetCooldownFromDurationObject(castInfo.duration)

            -- 중요 스펠 표시 (C_Spell.IsSpellImportant은 secret value → SetAlphaFromBoolean)
            if C_Spell.IsSpellImportant and castInfo.spellId then
                local isImportant = C_Spell.IsSpellImportant(castInfo.spellId)
                row.leftIcon.important:SetAlphaFromBoolean(isImportant)
                row.rightIcon.important:SetAlphaFromBoolean(isImportant)
            else
                row.leftIcon.important:SetAlpha(0)
                row.rightIcon.important:SetAlpha(0)
            end

            -- 남은 초 텍스트 (duration 숫자값은 secret 아님 - TargetedSpells 참고)
            if castInfo.duration then
                row.timeText:SetFormattedText("%.1f", castInfo.duration:GetRemainingDuration())
            end

            -- 플레이어 타겟팅 여부 (UnitIsUnit은 secret value → SetAlphaFromBoolean)
            local isTargetingPlayer = UnitIsUnit(castInfo.unit .. "target", "player")
            if onlyMe then
                -- onlyMe: 나를 타겟 → 보임(1), 아님 → 숨김(0)
                row:SetAlphaFromBoolean(isTargetingPlayer)
            else
                -- 전체 표시: 나를 타겟 → 밝게(1), 아님 → 어둡게(dimAlpha)
                row:SetAlphaFromBoolean(isTargetingPlayer, 1, dimAlpha)
            end

            -- 사운드 카운팅 (NotSecretValue fallback - secret이면 카운트 안 됨, 허용 가능)
            if NotSecretValue(isTargetingPlayer) and isTargetingPlayer then
                targetingCount = targetingCount + 1
            end

            currShow = currShow + 1
        end
    end

    -- 사운드 알림: N개 이상 동시 시전 시 (새로 도달했을 때만) -- [12.0.1] ns:PlaySound 통합
    local threshold = self.db.soundThreshold or 2
    if self.db.soundEnabled and targetingCount >= threshold and prevTargetingCount < threshold then
        local soundFile = self.db.soundFile
        local customPath = self.db.soundCustomPath
        if (customPath and customPath ~= "") or (soundFile and soundFile ~= "") then
            ns:PlaySound(soundFile, "Master", customPath)
        else
            PlaySound(SOUNDKIT.RAID_WARNING, "Master")
        end
    end
    prevTargetingCount = targetingCount

    -- 나머지 숨기기
    for i = currShow + 1, maxShow do
        if castFrames[i] then
            castFrames[i]:SetAlpha(0)
        end
    end
end

-- 이벤트 기반 업데이트 시작
function CastingAlert:StartUpdate()
    if updateTicker then
        updateTicker:Cancel()
        updateTicker = nil
    end

    -- 이벤트 프레임
    if not mainFrame.eventFrame then
        mainFrame.eventFrame = CreateFrame("Frame")
        mainFrame.eventFrame:SetScript("OnEvent", function(_, event, unit)
            if not unit or not string.find(unit, "nameplate") then return end

            if event == "NAME_PLATE_UNIT_REMOVED" then
                castingUnits[unit] = nil
                return
            end

            -- UnitCanAttack은 secret 아님 (TargetedSpells 참고 - 직접 boolean test 사용)
            -- UnitAffectingCombat, UnitClassification은 secret 가능 → 제거 (secret이면 모든 유닛 차단됨)
            if not UnitCanAttack("player", unit) then return end

            castingUnits[unit] = true  -- 다음 틱에서 체크
        end)
    end

    mainFrame.eventFrame:RegisterEvent("UNIT_SPELLCAST_START")
    mainFrame.eventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
    mainFrame.eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    mainFrame.eventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")

    -- 주기적 업데이트
    local rate = self.db.updateRate or 0.2
    updateTicker = C_Timer.NewTicker(rate, function()
        if not isEnabled or isTestMode then return end

        -- 시전 중인 유닛 갱신
        for unit, _ in pairs(castingUnits) do
            local isCasting, info = CheckCasting(unit)
            if isCasting then
                castingUnits[unit] = info
            else
                castingUnits[unit] = nil
            end
        end

        self:ShowCastings()
    end)

    mainFrame:Show()
end

-- 테스트 모드
function CastingAlert:TestMode()
    if not mainFrame then
        self:CreateMainFrame()
    end

    isTestMode = not isTestMode

    if isTestMode then
        mainFrame:EnableMouse(true)
        local size = self.db.iconSize or 35
        local rowSpacing = size + 4
        local maxShow = math.min(self.db.maxShow or 10, 3)
        for i = 1, maxShow do
            local row = castFrames[i]
            if row then
                row:ClearAllPoints()
                row:SetPoint("CENTER", mainFrame, "CENTER", 0, (i - 1) * rowSpacing)
                row.leftIcon.tex:SetTexture(134400)
                row.rightIcon.tex:SetTexture(134400)
                row.leftIcon.important:SetAlpha(i == 1 and 1 or 0)
                row.rightIcon.important:SetAlpha(i == 1 and 1 or 0)
                row.timeText:SetText(string.format("%.1f", 3.5 - i))
                row:SetAlpha(1)
            end
        end
        for i = maxShow + 1, (self.db.maxShow or 10) do
            if castFrames[i] then
                castFrames[i]:SetAlpha(0)
            end
        end
        print(CHAT_PREFIX .. "CastingAlert " .. L["TEST_MODE"] .. " ON") -- [STYLE]
    else
        mainFrame:EnableMouse(false)
        local maxShow = self.db.maxShow or 10
        for i = 1, maxShow do
            if castFrames[i] then
                castFrames[i]:SetAlpha(0)
            end
        end
        print(CHAT_PREFIX .. "CastingAlert " .. L["TEST_MODE"] .. " OFF") -- [STYLE]
    end
end

function CastingAlert:IsTestMode()
    return isTestMode
end

-- 스타일 업데이트
function CastingAlert:UpdateStyle()
    if not mainFrame then return end

    mainFrame:SetScale(self.db.scale or 1.0)

    local size = self.db.iconSize or 35
    local fontSize = self.db.fontSize or 18
    local textWidth = fontSize * 3
    local rowWidth = size + 4 + textWidth + 4 + size
    local maxShow = self.db.maxShow or 10

    for i = 1, maxShow do
        local row = castFrames[i]
        if row then
            row:SetSize(rowWidth, size)
            row.leftIcon:SetSize(size, size)
            row.rightIcon:SetSize(size, size)
            row.timeText:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")
        end
    end
end

-- 위치 업데이트 (설정에서 X/Y 변경 시)
function CastingAlert:UpdatePosition()
    if not mainFrame then return end
    local pos = self.db.position or {}
    mainFrame:ClearAllPoints()
    mainFrame:SetPoint(pos.point or "CENTER", UIParent, pos.relativePoint or "CENTER", pos.x or 0, pos.y or -30)
end

-- 위치 초기화
function CastingAlert:ResetPosition()
    if mainFrame then
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -30)
        self.db.position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -30 }
    end
end

-- 모듈 등록
DDingToolKit:RegisterModule("CastingAlert", CastingAlert)
