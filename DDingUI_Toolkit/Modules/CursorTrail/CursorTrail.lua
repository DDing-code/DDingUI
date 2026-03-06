--[[
    DDingToolKit - CursorTrail Module
    마우스 커서 트레일 효과
]]

local addonName, ns = ...
local DDingToolKit = ns.DDingToolKit
local UI = ns.UI

-- CursorTrail 모듈
local CursorTrail = {}
ns.CursorTrail = CursorTrail

-- 로컬 변수
local elementPool = {}
local activeElements = {}
local lastX, lastY = 0, 0
local trailFrame = nil
local isRunning = false
local toRemove = {}

-- 초기화
function CursorTrail:OnInitialize()
    self.db = ns.db.profile.CursorTrail

    -- 기존 DB 마이그레이션: 노란색/흰색 텍스처 → 회색 원 (색상 정확도 + 원형)
    if self.db.texture == "Interface\\COMMON\\Indicator-Yellow"
    or self.db.texture == "Interface\\Buttons\\WHITE8x8" then
        self.db.texture = "Interface\\COMMON\\Indicator-Gray"
    end
end

-- 활성화
function CursorTrail:OnEnable()
    self:CreateTrailFrame()
    self:CreateElementPool()

    if self.db.enabled and trailFrame then
        -- 커서 위치 초기화 (갑작스러운 트레일 점프 방지)
        local cursorX, cursorY = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        lastX, lastY = cursorX / scale, cursorY / scale

        trailFrame:Show()
        trailFrame:SetScript("OnUpdate", function(_, elapsed)
            self:OnUpdate(elapsed)
        end)
        isRunning = true
    end

    -- 설정창 열릴 때/닫힐 때 트레일 정리 (잔상 방지)
    C_Timer.After(0.5, function()
        local configFrame = ns.ConfigUI and ns.ConfigUI:GetFrame()
        if configFrame and not configFrame._cursorTrailHooked then
            configFrame:HookScript("OnShow", function()
                CursorTrail:ClearAllElements()
                local cursorX, cursorY = GetCursorPosition()
                local scale = UIParent:GetEffectiveScale()
                lastX, lastY = cursorX / scale, cursorY / scale
            end)
            configFrame:HookScript("OnHide", function()
                CursorTrail:ClearAllElements()
                local cursorX, cursorY = GetCursorPosition()
                local scale = UIParent:GetEffectiveScale()
                lastX, lastY = cursorX / scale, cursorY / scale
            end)
            configFrame._cursorTrailHooked = true
        end
    end)
end

-- 비활성화
function CursorTrail:OnDisable()
    isRunning = false
    self.db.enabled = false

    -- OnUpdate 먼저 중지
    if trailFrame then
        trailFrame:SetScript("OnUpdate", nil)
    end

    -- 모든 요소 제거
    self:ClearAllElements()

    -- 프레임 숨기기
    if trailFrame then
        trailFrame:Hide()
    end
end

-- 트레일 프레임 생성
function CursorTrail:CreateTrailFrame()
    if trailFrame then return end

    trailFrame = CreateFrame("Frame", "DDingToolKit_CursorTrailFrame", UIParent)
    trailFrame:SetFrameStrata(self.db.layer or "TOOLTIP")
    trailFrame:SetAllPoints(UIParent)
    trailFrame:Hide()
end

-- 오브젝트 풀 생성
function CursorTrail:CreateElementPool()
    -- activeElements도 Hide 처리 후 풀로 반환
    for _, element in ipairs(activeElements) do
        element:Hide()
        element:ClearAllPoints()
    end
    for _, element in ipairs(elementPool) do
        element:Hide()
        element:ClearAllPoints()
    end
    wipe(activeElements)

    if not trailFrame then return end

    local maxDots = math.min(self.db.maxDots or 800, 2000)

    -- 기존 풀보다 더 필요하면 추가 생성, 줄었으면 기존 것 재사용
    for i = #elementPool + 1, maxDots do
        local element = trailFrame:CreateTexture(nil, "OVERLAY")
        elementPool[i] = element
    end
    -- 초과분 숨기기
    for i = maxDots + 1, #elementPool do
        elementPool[i]:Hide()
    end

    -- 텍스처/블렌드 모드 설정 (기존 + 새로 생성된 요소 모두)
    for i = 1, maxDots do
        elementPool[i]:SetTexture(self.db.texture or "Interface\\COMMON\\Indicator-Gray")
        elementPool[i]:SetBlendMode(self.db.blendMode or "ADD")
        elementPool[i]:Hide()
    end
end

-- OnUpdate 핸들러
function CursorTrail:OnUpdate(elapsed)
    if not self.db.enabled then return end

    -- 설정창이 열려있을 때는 새 트레일 생성 안함 (잔상 방지)
    if ns.ConfigUI and ns.ConfigUI:IsShown() then
        self:UpdateActiveElements(elapsed)
        return
    end

    -- 조건 체크
    if self.db.onlyInCombat and not InCombatLockdown() then
        return
    end

    if self.db.hideInInstance then
        local inInstance, instanceType = IsInInstance()
        if inInstance and (instanceType == "party" or instanceType == "raid" or instanceType == "pvp" or instanceType == "arena") then
            return
        end
    end

    -- 현재 커서 위치
    local cursorX, cursorY = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    cursorX, cursorY = cursorX / scale, cursorY / scale

    -- 이동 거리 계산
    local xDiff = cursorX - lastX
    local yDiff = cursorY - lastY
    local distance = math.sqrt(xDiff * xDiff + yDiff * yDiff)

    -- 최소 거리 이상 움직였을 때만 새 점 생성
    local dotDistance = self.db.dotDistance or 2
    if distance >= dotDistance then
        local steps = math.floor(distance / dotDistance)

        for i = 1, steps do
            if #elementPool > 0 then
                local ratio = i / steps
                local elementX = lastX + xDiff * ratio
                local elementY = lastY + yDiff * ratio

                -- 풀에서 요소 가져오기
                local element = table.remove(elementPool)

                -- 요소 설정
                local lifetime = self.db.lifetime or 0.25
                element.duration = lifetime
                element.totalDuration = lifetime
                element.spawnTime = GetTime()
                element:SetSize(self.db.width or 60, self.db.height or 60)
                element:SetAlpha(self.db.alpha or 1.0)
                element:ClearAllPoints()
                element:SetPoint("CENTER", UIParent, "BOTTOMLEFT", elementX, elementY)
                element:Show()

                table.insert(activeElements, element)
            end
        end

        lastX, lastY = cursorX, cursorY
    end

    -- 활성 요소 업데이트
    self:UpdateActiveElements(elapsed)
end

-- 활성 요소 업데이트
function CursorTrail:UpdateActiveElements(elapsed)
    local db = self.db
    wipe(toRemove)

    for i, element in ipairs(activeElements) do
        element.duration = element.duration - elapsed

        if element.duration <= 0 then
            -- 수명 끝 - 풀로 반환
            element:Hide()
            table.insert(elementPool, element)
            table.insert(toRemove, i)
        else
            -- 크기 & 알파 감소
            local lifeRatio = element.duration / element.totalDuration
            local currentScale = math.max(0.2, lifeRatio)
            local currentAlpha = (db.alpha or 1.0) * lifeRatio

            element:SetSize((db.width or 60) * currentScale, (db.height or 60) * currentScale)
            element:SetAlpha(currentAlpha)

            -- 색상 계산
            local r, g, b
            if db.colorFlow then
                r, g, b = self:GetTimeBasedColor(element.spawnTime)
            else
                r, g, b = self:GetLifetimeBasedColor(lifeRatio)
            end
            element:SetVertexColor(r, g, b, currentAlpha)
        end
    end

    -- [PERF] 제거: swap-remove 패턴 (O(n) table.remove → O(1) swap)
    for i = #toRemove, 1, -1 do
        local idx = toRemove[i]
        local last = #activeElements
        if idx ~= last then
            activeElements[idx] = activeElements[last]
        end
        activeElements[last] = nil
    end
end

-- 수명 기반 색상 (그라데이션)
function CursorTrail:GetLifetimeBasedColor(lifeRatio)
    local db = self.db
    local numColors = db.colorCount or 8
    local colors = db.colors

    if not colors or numColors < 1 then
        return 1, 1, 1
    end

    -- 진행도에 따른 색상 인덱스
    local progress = (1 - lifeRatio) * numColors
    local currentIdx = math.min(math.floor(progress), numColors - 1)
    local nextIdx = math.min(currentIdx + 1, numColors - 1)
    local fraction = progress - currentIdx

    -- 색상 보간
    local c1 = colors[currentIdx + 1]
    local c2 = colors[nextIdx + 1]

    if not c1 or not c2 then
        return 1, 1, 1
    end

    local r = c1[1] + (c2[1] - c1[1]) * fraction
    local g = c1[2] + (c2[2] - c1[2]) * fraction
    local b = c1[3] + (c2[3] - c1[3]) * fraction

    return r, g, b
end

-- 시간 기반 색상 (무지개 플로우)
function CursorTrail:GetTimeBasedColor(spawnTime)
    local db = self.db
    local numColors = db.colorCount or 8
    local colors = db.colors

    if not colors or numColors < 1 then
        return 1, 1, 1
    end

    local elapsedTime = GetTime() - spawnTime
    local cycleDuration = db.colorFlowSpeed or 0.6
    local phaseDuration = cycleDuration / numColors
    local phaseProgress = (elapsedTime % cycleDuration) / phaseDuration

    local currentPhase = math.floor(phaseProgress) % numColors
    local nextPhase = (currentPhase + 1) % numColors
    local fraction = phaseProgress - math.floor(phaseProgress)

    local c1 = colors[nextPhase + 1]
    local c2 = colors[currentPhase + 1]

    if not c1 or not c2 then
        return 1, 1, 1
    end

    local r = c2[1] + (c1[1] - c2[1]) * fraction
    local g = c2[2] + (c1[2] - c2[2]) * fraction
    local b = c2[3] + (c1[3] - c2[3]) * fraction

    return r, g, b
end

-- 모든 요소 제거
function CursorTrail:ClearAllElements()
    -- 활성 요소 숨기기 및 풀로 반환
    for _, element in ipairs(activeElements) do
        element:Hide()
        element:ClearAllPoints()
        element:SetAlpha(0)
        table.insert(elementPool, element)
    end
    wipe(activeElements)

    -- 풀의 모든 요소도 확실히 숨기기
    for _, element in ipairs(elementPool) do
        element:Hide()
        element:ClearAllPoints()
        element:SetAlpha(0)
    end
end

-- 설정 변경 시 호출
function CursorTrail:ApplySettings()
    if trailFrame then
        trailFrame:SetFrameStrata(self.db.layer or "TOOLTIP")
    end

    -- 블렌드 모드 변경 시 풀 재생성
    self:ClearAllElements()
    for _, element in ipairs(elementPool) do
        element:SetTexture(self.db.texture or "Interface\\COMMON\\Indicator-Gray")
        element:SetBlendMode(self.db.blendMode or "ADD")
    end
end

-- 프리셋 적용
function CursorTrail:ApplyPreset(presetName)
    local preset = ns.CursorTrailPresets[presetName]
    if not preset then return end

    self.db.colorCount = preset.colorCount
    for i = 1, 10 do
        if preset.colors[i] then
            self.db.colors[i] = { unpack(preset.colors[i]) }
        end
    end
    self.db.colorFlow = preset.colorFlow or false
    self.db.colorFlowSpeed = preset.colorFlowSpeed or 0.6
    self.db.preset = presetName

    self:ApplySettings()
end

-- 트레일 토글
function CursorTrail:Toggle()
    self.db.enabled = not self.db.enabled
    if self.db.enabled then
        if trailFrame then
            -- 커서 위치 초기화 (갑작스러운 트레일 점프 방지)
            local cursorX, cursorY = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            lastX, lastY = cursorX / scale, cursorY / scale

            trailFrame:Show()
            trailFrame:SetScript("OnUpdate", function(_, elapsed)
                self:OnUpdate(elapsed)
            end)
            isRunning = true
        end
    else
        isRunning = false

        -- OnUpdate 먼저 중지
        if trailFrame then
            trailFrame:SetScript("OnUpdate", nil)
        end

        -- 모든 요소 제거
        self:ClearAllElements()

        -- 프레임 숨기기
        if trailFrame then
            trailFrame:Hide()
        end
    end
    return self.db.enabled
end

-- 모듈 등록
DDingToolKit:RegisterModule("CursorTrail", CursorTrail)
