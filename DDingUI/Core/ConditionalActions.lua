-- =============================================================================
-- DDingUI Conditional Actions Engine
-- 그룹 다중 트리거 → 동작(Actions) 시스템
-- =============================================================================
local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
local L = ns.L or {}

-- ─── Constants ───
local EVAL_INTERVAL = 0.1  -- 평가 주기 (초)
local evalElapsed = 0

-- 동작 대상 프레임 해석
local function ResolveBarFrame(target, group, trackedBuffs)
    if target == "PrimaryPowerBar" then
        return DDingUI.powerBar
    elseif target == "SecondaryPowerBar" then
        return DDingUI.secondaryPowerBar
    elseif target == "CastBar" then
        return DDingUI.castBar
    end

    -- BuffTracker 바 대상: bt_child_N
    local childMatch = target and target:match("^bt_child_(%d+)$")
    if childMatch and group then
        local ci = tonumber(childMatch)
        local children = group.controlledChildren or {}
        local childIdx = children[ci]
        if childIdx and DDingUI._buffTrackerBars then
            return DDingUI._buffTrackerBars[childIdx]
        end
    end

    return nil
end

-- ─── Trigger 상태 읽기 ───
-- CDMScanner 캐시 기반 (secret-safe)
local function GetTriggerState(trigger, group, trackedBuffs)
    local buff
    if trigger.source == "child" then
        local children = group.controlledChildren or {}
        local childIdx = children[trigger.childIndex]
        buff = childIdx and trackedBuffs[childIdx]
    elseif trigger.source == "spell" then
        for _, b in ipairs(trackedBuffs) do
            if b.spellID == trigger.spellID then
                buff = b
                break
            end
        end
    end
    if not buff then return 0, 1, 0, false, false, false end

    local stacks = 0
    local maxStacks = (buff.settings and buff.settings.maxStacks) or 1
    local duration = 0
    local hasAura = false
    local cooldownReady = false
    local cooldownActive = false

    -- 실제 사용할 spellID 결정 (displaySpellID > trigger.spellID > cooldownID > spellID)
    local effectiveSpellID = buff.spellID
    if buff.trigger and buff.trigger.spellID and buff.trigger.spellID > 0 then
        effectiveSpellID = buff.trigger.spellID
    end
    if buff.cooldownID and buff.cooldownID > 0 then
        -- cooldownID가 effectiveSpellID와 다르면 둘 다 시도
    end

    -- ─── 1) Aura 감지 (버프/디버프) ───
    -- 여러 spellID로 시도 (base, effective, cooldownID)
    local spellIDsToCheck = {}
    if effectiveSpellID and effectiveSpellID > 0 then
        spellIDsToCheck[#spellIDsToCheck + 1] = effectiveSpellID
    end
    if buff.spellID and buff.spellID > 0 and buff.spellID ~= effectiveSpellID then
        spellIDsToCheck[#spellIDsToCheck + 1] = buff.spellID
    end
    if buff.cooldownID and buff.cooldownID > 0 
       and buff.cooldownID ~= effectiveSpellID and buff.cooldownID ~= buff.spellID then
        spellIDsToCheck[#spellIDsToCheck + 1] = buff.cooldownID
    end

    for _, sid in ipairs(spellIDsToCheck) do
        if hasAura then break end
        pcall(function()
            local auraData = C_UnitAuras.GetPlayerAuraBySpellID(sid)
            if auraData then
                hasAura = true
                -- duration: expirationTime은 secret-safe
                if auraData.expirationTime then
                    local remaining = auraData.expirationTime - GetTime()
                    if type(remaining) == "number" and remaining > 0 then
                        duration = remaining
                    end
                end
            end
        end)
    end

    -- ─── 2) 쿨다운 상태 (secret-safe) ───
    local cdSpellID = effectiveSpellID or buff.spellID
    if cdSpellID and cdSpellID > 0 then
        -- charge 기반 스펠 먼저 확인
        pcall(function()
            local chargeInfo = C_Spell.GetSpellCharges(cdSpellID)
            if chargeInfo then
                local ok, charges = pcall(tonumber, chargeInfo.currentCharges)
                local ok2, maxCharges = pcall(tonumber, chargeInfo.maxCharges)
                if ok and charges then
                    stacks = charges  -- charge를 stacks로 매핑
                    if ok2 and maxCharges then
                        maxStacks = maxCharges
                    end
                    -- charge가 만들어 주는 상태
                    if charges > 0 then
                        cooldownReady = true
                        cooldownActive = false
                    end
                    if charges < (maxCharges or 1) then
                        cooldownActive = true
                    end
                end
            end
        end)

        -- 일반 쿨다운 (charge가 없는 경우)
        if not cooldownReady and not cooldownActive then
            pcall(function()
                local cdInfo = C_Spell.GetSpellCooldown(cdSpellID)
                if cdInfo then
                    -- startTime과 duration을 tonumber로 안전 변환
                    local okS, startTime = pcall(tonumber, cdInfo.startTime)
                    local okD, dur = pcall(tonumber, cdInfo.duration)
                    if okS and okD and startTime and dur then
                        -- GCD (duration <= 1.5) 무시 — 실제 쿨다운만 체크
                        if dur > 1.5 then
                            cooldownActive = true
                            cooldownReady = false
                            -- 남은 쿨다운을 duration에 저장 (aura duration이 없을 때)
                            if duration == 0 then
                                local remaining = (startTime + dur) - GetTime()
                                if remaining > 0 then
                                    duration = remaining
                                end
                            end
                        else
                            cooldownReady = true
                            cooldownActive = false
                        end
                    else
                        -- tonumber 실패 = secret value → IsSpellUsable로 판정
                        local okU, usable = pcall(C_Spell.IsSpellUsable, cdSpellID)
                        if okU then
                            if usable then
                                cooldownReady = true
                                cooldownActive = false
                            else
                                cooldownActive = true
                                cooldownReady = false
                            end
                        end
                    end
                end
            end)
        end
    end

    -- ─── 3) CDMScanner 보조 (stacks 보강) ───
    local CDMScanner = DDingUI.CDMScanner
    local cdID = buff.cooldownID
    if cdID and CDMScanner and stacks == 0 then
        pcall(function()
            local entry = CDMScanner.GetEntry(cdID)
            if entry and entry.iconFrame then
                local stackText = entry.iconFrame.Count or entry.iconFrame.count
                if stackText and stackText.GetText then
                    local text = stackText:GetText()
                    if text and text ~= "" then
                        local n = tonumber(text)
                        if n and n > 0 then
                            stacks = n
                        end
                    end
                end
            end
        end)
    end

    -- ─── 4) spell 모드에서 hasAura 판정 보강 ───
    -- spell 모드 트래커는 aura가 아니지만, 쿨다운 상태로 "활성" 판정 가능
    if buff.trackingMode == "spell" and not hasAura then
        -- cooldownActive면 "스펠이 사용됨" = 활성으로 간주
        if cooldownActive then
            hasAura = true
        end
    end

    return stacks, maxStacks, duration, hasAura, cooldownReady, cooldownActive
end

-- secret value 안전 비교 함수
local function SafeCompare(a, b, op)
    -- issecretvalue가 있으면 비교 불가 → 항상 false
    if issecretvalue and (issecretvalue(a) or issecretvalue(b)) then return false end
    if type(a) ~= "number" or type(b) ~= "number" then return false end
    if op == "gte" then return a >= b
    elseif op == "lte" then return a <= b
    elseif op == "eq" then return a == b
    end
    return false
end

-- ─── 조건 체크 ───
local function CheckCondition(condition, value, state)
    if condition == "active" then
        return state.hasAura == true
    elseif condition == "inactive" then
        return state.hasAura == false or state.hasAura == nil
    elseif condition == "duration_gte" then
        return SafeCompare(state.duration, value or 0, "gte")
    elseif condition == "duration_lte" then
        return state.hasAura and SafeCompare(state.duration, 0, "gte") and SafeCompare(state.duration, value or 0, "lte")
    elseif condition == "cooldown_ready" then
        return state.cooldownReady == true
    elseif condition == "cooldown_active" then
        return state.cooldownActive == true
    end
    return false
end

-- ─── 트리거 평가 (단일 세트) ───
local function EvaluateSetTriggers(set, group, trackedBuffs)
    if not set.triggers or #set.triggers == 0 then return false end

    local results = {}
    for i, trigger in ipairs(set.triggers) do
        local stacks, maxStacks, duration, hasAura, cdReady, cdActive = GetTriggerState(trigger, group, trackedBuffs)
        -- duration 조건에 maxDuration 설정이 있으면 수동 계산
        -- API에서 duration을 못 읽거나 (secret value) 수동 계산을 원할 때 사용
        local cond = trigger.condition or "active"
        if (cond == "duration_gte" or cond == "duration_lte") and trigger.maxDuration and trigger.maxDuration > 0 then
            -- 버프 활성화 시점 추적 키
            local trackKey = "_auraStart_" .. (trigger.source or "") .. "_" .. tostring(trigger.childIndex or trigger.spellID or 0)
            if hasAura then
                if not set[trackKey] then
                    set[trackKey] = GetTime()  -- 버프 활성화 시점 기록
                end
                local elapsed = GetTime() - set[trackKey]
                duration = math.max(0, trigger.maxDuration - elapsed)
            else
                set[trackKey] = nil  -- 버프 비활성화 시 시점 초기화
                duration = 0
            end
        end

        results[i] = CheckCondition(cond, trigger.value, {
            stacks = stacks,
            maxStacks = maxStacks,
            duration = duration,
            hasAura = hasAura,
            cooldownReady = cdReady,
            cooldownActive = cdActive,
        })
    end

    -- AND/OR 논리
    if set.logic == "or" then
        for _, r in ipairs(results) do
            if r then return true end
        end
        return false
    else -- "and" (기본값)
        for _, r in ipairs(results) do
            if not r then return false end
        end
        return true
    end
end

-- 기존 flat 구조 호환 래퍼
local function EvaluateGroupTriggers(group, trackedBuffs)
    local ca = group.groupSettings and group.groupSettings.conditionalActions
    if not ca or not ca.enabled then return false end
    -- sets 구조: 하나라도 true면 true (세트 간은 OR)
    if ca.sets and #ca.sets > 0 then
        for _, set in ipairs(ca.sets) do
            if EvaluateSetTriggers(set, group, trackedBuffs) then
                return true
            end
        end
        return false
    end
    -- 기존 flat 구조 호환
    if not ca.triggers or #ca.triggers == 0 then return false end
    return EvaluateSetTriggers(ca, group, trackedBuffs)
end

-- ─── 글로우 효과 ───
local glowFrames = {}  -- 활성 글로우 프레임 추적

local function ShowBarGlow(bar, color, intensity)
    if not bar then return end
    local glowKey = tostring(bar)

    if not glowFrames[glowKey] then
        local glow = CreateFrame("Frame", nil, bar)
        glow:SetAllPoints(bar)
        glow:SetFrameLevel(bar:GetFrameLevel() + 20)

        -- 상단 글로우
        local top = glow:CreateTexture(nil, "OVERLAY")
        top:SetPoint("TOPLEFT", bar, "TOPLEFT", -2, 2)
        top:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 2, 2)
        top:SetHeight(3)
        top:SetBlendMode("ADD")
        glow._top = top

        -- 하단 글로우
        local bottom = glow:CreateTexture(nil, "OVERLAY")
        bottom:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", -2, -2)
        bottom:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 2, -2)
        bottom:SetHeight(3)
        bottom:SetBlendMode("ADD")
        glow._bottom = bottom

        -- 좌측 글로우
        local left = glow:CreateTexture(nil, "OVERLAY")
        left:SetPoint("TOPLEFT", bar, "TOPLEFT", -2, 2)
        left:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", -2, -2)
        left:SetWidth(3)
        left:SetBlendMode("ADD")
        glow._left = left

        -- 우측 글로우
        local right = glow:CreateTexture(nil, "OVERLAY")
        right:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 2, 2)
        right:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 2, -2)
        right:SetWidth(3)
        right:SetBlendMode("ADD")
        glow._right = right

        glowFrames[glowKey] = glow
    end

    local glow = glowFrames[glowKey]
    local c = color or {1, 0.8, 0.2, 0.8}
    local int = (intensity or 0.6) * 1.5

    for _, texKey in ipairs({"_top", "_bottom", "_left", "_right"}) do
        local tex = glow[texKey]
        tex:SetColorTexture(c[1] * int, c[2] * int, c[3] * int, c[4] or 0.8)
    end

    -- 펄스 애니메이션
    if not glow._pulseAG then
        local ag = glow:CreateAnimationGroup()
        ag:SetLooping("BOUNCE")
        local pulse = ag:CreateAnimation("Alpha")
        pulse:SetFromAlpha(0.4)
        pulse:SetToAlpha(1.0)
        pulse:SetDuration(0.6)
        pulse:SetSmoothing("IN_OUT")
        glow._pulseAG = ag
    end
    glow._pulseAG:Play()
    glow:Show()
end

local function HideBarGlow(bar)
    if not bar then return end
    local glowKey = tostring(bar)
    local glow = glowFrames[glowKey]
    if glow then
        if glow._pulseAG then glow._pulseAG:Stop() end
        glow:Hide()
    end
end

-- ─── 아이콘 글로우 ───
local iconGlowActive = {}  -- 활성 아이콘 글로우 추적

local function ShowIconGlow(cooldownID, color)
    if not cooldownID then return end
    local CDMScanner = DDingUI.CDMScanner
    if not CDMScanner then return end

    local entry = CDMScanner.GetEntry(cooldownID)
    if not entry then return end

    local frame = entry.iconFrame or entry.frame
    if not frame then return end

    local glowKey = tostring(frame)
    if iconGlowActive[glowKey] then return end  -- 이미 활성

    -- ActionButton_ShowOverlayGlow 사용 (블리자드 내장)
    pcall(function()
        if ActionButton_ShowOverlayGlow then
            ActionButton_ShowOverlayGlow(frame)
        elseif frame.SetGlow then
            frame:SetGlow(true)
        end
    end)
    iconGlowActive[glowKey] = true
end

local function HideIconGlow(cooldownID)
    if not cooldownID then return end
    local CDMScanner = DDingUI.CDMScanner
    if not CDMScanner then return end

    local entry = CDMScanner.GetEntry(cooldownID)
    if not entry then return end

    local frame = entry.iconFrame or entry.frame
    if not frame then return end

    local glowKey = tostring(frame)
    if not iconGlowActive[glowKey] then return end

    pcall(function()
        if ActionButton_HideOverlayGlow then
            ActionButton_HideOverlayGlow(frame)
        elseif frame.SetGlow then
            frame:SetGlow(false)
        end
    end)
    iconGlowActive[glowKey] = nil
end

-- ─── 텍스트 알림 ───
local alertTextFrame = nil

local function ShowAlertText(text, color, duration, size, position)
    if not alertTextFrame then
        alertTextFrame = CreateFrame("Frame", "DDingUI_AlertText", UIParent)
        alertTextFrame:SetSize(400, 50)
        alertTextFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        alertTextFrame:SetFrameLevel(300)

        local fs = alertTextFrame:CreateFontString(nil, "OVERLAY")
        fs:SetAllPoints()
        fs:SetJustifyH("CENTER")
        fs:SetJustifyV("MIDDLE")
        alertTextFrame._text = fs

        alertTextFrame:Hide()
    end

    local c = color or {1, 1, 0, 1}
    local sz = size or 28

    alertTextFrame:ClearAllPoints()
    local pos = position or "CENTER"
    if pos == "TOP" then
        alertTextFrame:SetPoint("TOP", UIParent, "TOP", 0, -200)
    elseif pos == "BOTTOM" then
        alertTextFrame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 200)
    else
        alertTextFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    end

    local font = DDingUI.GetFont and DDingUI:GetFont() or "Fonts\\FRIZQT__.TTF"
    alertTextFrame._text:SetFont(font, sz, "OUTLINE")
    alertTextFrame._text:SetText(text or "")
    alertTextFrame._text:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    alertTextFrame:SetAlpha(1)
    alertTextFrame:Show()

    -- 페이드 아웃
    local dur = duration or 2
    C_Timer.After(dur * 0.7, function()
        if alertTextFrame and alertTextFrame:IsShown() then
            -- 간단한 페이드 아웃 (0.3초)
            local fadeElapsed = 0
            alertTextFrame:SetScript("OnUpdate", function(self, elapsed)
                fadeElapsed = fadeElapsed + elapsed
                local alpha = 1 - (fadeElapsed / (dur * 0.3))
                if alpha <= 0 then
                    self:Hide()
                    self:SetScript("OnUpdate", nil)
                else
                    self:SetAlpha(alpha)
                end
            end)
        end
    end)
end

-- ─── 액션 실행 ───
local function ExecuteActions(actions, shouldFire, group, trackedBuffs)
    for _, action in ipairs(actions) do
        -- ─── 바 색상 변경 ───
        if action.type == "bar_color" then
            local bar = ResolveBarFrame(action.target, group, trackedBuffs)
            if bar then
                if shouldFire then
                    bar._ddingColorOverride = action.color
                else
                    bar._ddingColorOverride = nil
                end
            end

        -- ─── 바 글로우 ───
        elseif action.type == "bar_glow" then
            local bar = ResolveBarFrame(action.target, group, trackedBuffs)
            if bar then
                if shouldFire then
                    ShowBarGlow(bar, action.color, action.intensity)
                    bar._ddingGlowActive = true
                else
                    HideBarGlow(bar)
                    bar._ddingGlowActive = nil
                end
            end

        -- ─── 아이콘 글로우 ───
        elseif action.type == "icon_glow" then
            local cdID
            if action.childIndex then
                local children = group.controlledChildren or {}
                local childIdx = children[action.childIndex]
                local buff = childIdx and trackedBuffs[childIdx]
                cdID = buff and buff.cooldownID
            elseif action.spellID then
                -- spellID로 cooldownID 조회
                for _, b in ipairs(trackedBuffs) do
                    if b.spellID == action.spellID then
                        cdID = b.cooldownID
                        break
                    end
                end
            end
            if cdID then
                if shouldFire then
                    ShowIconGlow(cdID, action.color)
                else
                    HideIconGlow(cdID)
                end
            end

        -- ─── 아이콘 텍스처 변경 ───
        elseif action.type == "icon_change" then
            local cdID
            if action.childIndex then
                local children = group.controlledChildren or {}
                local childIdx = children[action.childIndex]
                local buff = childIdx and trackedBuffs[childIdx]
                cdID = buff and buff.cooldownID
            end
            if cdID then
                local CDMScanner = DDingUI.CDMScanner
                local entry = CDMScanner and CDMScanner.GetEntry(cdID)
                if entry then
                    local frame = entry.iconFrame or entry.frame
                    if frame then
                        pcall(function()
                            local iconTex = frame.Icon or frame.icon
                            if iconTex and iconTex.SetTexture then
                                if shouldFire and action.newIconID then
                                    if not frame._ddingOrigIcon then
                                        frame._ddingOrigIcon = iconTex:GetTexture()
                                    end
                                    iconTex:SetTexture(action.newIconID)
                                elseif not shouldFire and frame._ddingOrigIcon then
                                    iconTex:SetTexture(frame._ddingOrigIcon)
                                    frame._ddingOrigIcon = nil
                                end
                            end
                        end)
                    end
                end
            end

        -- ─── 사운드 재생 ───
        elseif action.type == "play_sound" then
            if shouldFire then
                local now = GetTime()
                local cooldown = action.cooldown or 3
                if not group._lastSoundTime or (now - group._lastSoundTime) >= cooldown then
                    pcall(function()
                        local soundFile = action.soundFile
                        if soundFile then
                            local channel = action.channel or "Master"
                            -- SharedMedia 체크
                            local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
                            if LSM then
                                local mediaPath = LSM:Fetch("sound", soundFile)
                                if mediaPath then soundFile = mediaPath end
                            end
                            PlaySoundFile(soundFile, channel)
                        end
                    end)
                    group._lastSoundTime = now
                end
            else
                group._lastSoundTime = nil
            end

        -- ─── 텍스트 알림 ───
        elseif action.type == "show_text" then
            if shouldFire then
                local now = GetTime()
                local cooldown = (action.duration or 2) + 1
                if not group._lastTextTime or (now - group._lastTextTime) >= cooldown then
                    ShowAlertText(action.text, action.color, action.duration, action.size, action.position)
                    group._lastTextTime = now
                end
            else
                group._lastTextTime = nil
            end
        end
    end
end

-- ─── 메인 OnUpdate 루프 ───
local evaluationFrame = CreateFrame("Frame", "DDingUI_ConditionalActionsFrame", UIParent)

local function GetTrackedBuffs()
    if not DDingUI.db then return {} end
    local specIndex = GetSpecialization and GetSpecialization()
    local specID = specIndex and GetSpecializationInfo(specIndex) or nil
    local globalStore = DDingUI.db.global and DDingUI.db.global.trackedBuffsPerSpec
    if specID and globalStore and globalStore[specID] then
        return globalStore[specID]
    end
    if DDingUI.db.profile.buffTrackerBar and DDingUI.db.profile.buffTrackerBar.trackedBuffs then
        return DDingUI.db.profile.buffTrackerBar.trackedBuffs
    end
    return {}
end

evaluationFrame:SetScript("OnUpdate", function(self, elapsed)
    evalElapsed = evalElapsed + elapsed
    if evalElapsed < EVAL_INTERVAL then return end
    evalElapsed = 0

    local trackedBuffs = GetTrackedBuffs()
    if not trackedBuffs or #trackedBuffs == 0 then return end


    for i, group in ipairs(trackedBuffs) do
        if group.isGroup and group.groupSettings
           and group.groupSettings.conditionalActions
           and group.groupSettings.conditionalActions.enabled then
            local ca = group.groupSettings.conditionalActions

            -- sets 구조: 각 세트별 독립 평가 + 독립 실행
            if ca.sets and #ca.sets > 0 then
                for si, set in ipairs(ca.sets) do
                    local shouldFire = EvaluateSetTriggers(set, group, trackedBuffs)
                    local stateKey = "_setTriggerState_" .. si
                    if shouldFire ~= group[stateKey] then
                        group[stateKey] = shouldFire
                        ExecuteActions(
                            set.actions or {},
                            shouldFire,
                            group,
                            trackedBuffs
                        )
                    end
                end
            else
                -- 기존 flat 구조 호환
                local shouldFire = EvaluateGroupTriggers(group, trackedBuffs)
                if shouldFire ~= group._lastTriggerState then
                    group._lastTriggerState = shouldFire
                    ExecuteActions(
                        ca.actions or {},
                        shouldFire,
                        group,
                        trackedBuffs
                    )
                end
            end
        end
    end
end)

-- ─── Public API ───
DDingUI.ConditionalActions = {
    Evaluate = EvaluateGroupTriggers,
    Execute = ExecuteActions,
    ShowBarGlow = ShowBarGlow,
    HideBarGlow = HideBarGlow,
    ShowIconGlow = ShowIconGlow,
    HideIconGlow = HideIconGlow,
    ShowAlertText = ShowAlertText,
    ResolveBarFrame = ResolveBarFrame,
    -- 조건 목록 (GUI용)
    CONDITIONS = {
        { id = "active",          name = L["Active"] or "Active",                   needsValue = false },
        { id = "inactive",        name = L["Inactive"] or "Inactive",               needsValue = false },
        { id = "duration_gte",    name = L["Duration ≥"] or "Duration ≥",          needsValue = true, needsMaxDuration = true  },
        { id = "duration_lte",    name = L["Duration ≤"] or "Duration ≤",          needsValue = true, needsMaxDuration = true  },
        { id = "cooldown_ready",  name = L["Cooldown Ready"] or "Cooldown Ready",   needsValue = false },
        { id = "cooldown_active", name = L["Cooldown Active"] or "Cooldown Active", needsValue = false },
    },
    -- 액션 타입 목록 (GUI용)
    ACTION_TYPES = {
        { id = "bar_color",   name = L["Bar Color Change"] or "Bar Color Change",     category = "bar"   },
        { id = "bar_glow",    name = L["Bar Glow"] or "Bar Glow",                     category = "bar"   },
        { id = "icon_glow",   name = L["Icon Glow"] or "Icon Glow",                   category = "icon"  },
        { id = "icon_change", name = L["Icon Change"] or "Icon Texture Change",       category = "icon"  },
        { id = "play_sound",  name = L["Play Sound"] or "Play Sound",                 category = "sound" },
        { id = "show_text",   name = L["Show Text"] or "Show Alert Text",             category = "text"  },
    },
    -- 대상 바 목록 (GUI용)
    BAR_TARGETS = {
        { id = "PrimaryPowerBar",   name = L["Primary Power Bar"] or "Primary Power Bar"     },
        { id = "SecondaryPowerBar", name = L["Secondary Power Bar"] or "Secondary Power Bar" },
        { id = "CastBar",          name = L["Cast Bar"] or "Cast Bar"                        },
    },
}

-- ─── 툴팁에서 지속시간 자동 추출 ───
-- 트리거 조건 UI에서 maxDuration 자동 채우기에 사용
-- C_Spell.GetSpellDescription 및 C_TooltipInfo 양쪽 모두 시도
function DDingUI.ExtractDurationFromTooltip(spellID)
    if not spellID or spellID == 0 then return nil end

    -- 지속시간 패턴 (초/분 단위, 한국어/영어)
    local function ParseDurationText(text)
        if not text or text == "" then return nil end

        -- 한국어: "12초 동안", "12초간", "12초", "1.5초"
        local secKR = text:match("(%d+%.?%d*)%s*초")
        if secKR then return tonumber(secKR) end

        -- 한국어: "12분 동안", "12분간", "1분"
        local minKR = text:match("(%d+%.?%d*)%s*분")
        if minKR then return tonumber(minKR) * 60 end

        -- 영어: "for 12 sec", "lasts 12 sec", "12 seconds", "12 sec"
        local secEN = text:match("(%d+%.?%d*)%s+sec")
        if secEN then return tonumber(secEN) end

        -- 영어: "for 12 min", "12 minutes"
        local minEN = text:match("(%d+%.?%d*)%s+min")
        if minEN then return tonumber(minEN) * 60 end

        return nil
    end

    -- 1차: C_Spell.GetSpellDescription (가장 간단)
    local ok1, desc = pcall(C_Spell.GetSpellDescription, spellID)
    if ok1 and desc then
        local d = ParseDurationText(desc)
        if d then return d end
    end

    -- 2차: C_TooltipInfo.GetSpellByID (구조화된 툴팁 데이터)
    if C_TooltipInfo and C_TooltipInfo.GetSpellByID then
        local ok2, tooltipData = pcall(C_TooltipInfo.GetSpellByID, spellID)
        if ok2 and tooltipData and tooltipData.lines then
            for _, line in ipairs(tooltipData.lines) do
                local lineText = line.leftText
                if lineText then
                    local d = ParseDurationText(lineText)
                    if d then return d end
                end
                -- rightText에도 지속시간이 있을 수 있음
                local rightText = line.rightText
                if rightText then
                    local d = ParseDurationText(rightText)
                    if d then return d end
                end
            end
        end
    end

    return nil
end
