------------------------------------------------------
-- DDingUI_StyleLib :: Animation
-- 애니메이션 헬퍼 (inspired by AbstractFramework)
-- FadeIn/Out, SlideIn/Out, Pulse, Flash
------------------------------------------------------
local MAJOR = "DDingUI-StyleLib-1.0"
local Lib = LibStub:GetLibrary(MAJOR)
if not Lib then return end

---------------------------------------------------------------------
-- FadeIn / FadeOut
---------------------------------------------------------------------

--- 프레임을 부드럽게 나타나게 합니다.
--- @param frame Frame
--- @param duration number|nil  기본 0.2초
--- @param startAlpha number|nil  기본 0
--- @param endAlpha number|nil  기본 1
--- @param onFinish function|nil
function Lib.FadeIn(frame, duration, startAlpha, endAlpha, onFinish)
    duration = duration or 0.2
    startAlpha = startAlpha or 0
    endAlpha = endAlpha or 1

    if not frame._slFadeIn then
        local ag = frame:CreateAnimationGroup()
        local anim = ag:CreateAnimation("Alpha")
        frame._slFadeIn = ag
        frame._slFadeInAnim = anim
        anim:SetSmoothing("IN")
    end

    -- 진행 중인 FadeOut 중지
    if frame._slFadeOut and frame._slFadeOut:IsPlaying() then
        frame._slFadeOut:Stop()
    end

    local ag = frame._slFadeIn
    local anim = frame._slFadeInAnim

    anim:SetDuration(duration)
    anim:SetFromAlpha(startAlpha)
    anim:SetToAlpha(endAlpha)

    ag:SetScript("OnFinished", function()
        frame:SetAlpha(endAlpha)
        if onFinish then onFinish(frame) end
    end)

    frame:SetAlpha(startAlpha)
    frame:Show()
    ag:Play()
end

--- 프레임을 부드럽게 사라지게 합니다.
--- @param frame Frame
--- @param duration number|nil  기본 0.2초
--- @param startAlpha number|nil  기본 현재 알파
--- @param endAlpha number|nil  기본 0
--- @param hideOnFinish boolean|nil  기본 true
--- @param onFinish function|nil
function Lib.FadeOut(frame, duration, startAlpha, endAlpha, hideOnFinish, onFinish)
    duration = duration or 0.2
    startAlpha = startAlpha or frame:GetAlpha()
    endAlpha = endAlpha or 0
    if hideOnFinish == nil then hideOnFinish = true end

    if not frame._slFadeOut then
        local ag = frame:CreateAnimationGroup()
        local anim = ag:CreateAnimation("Alpha")
        frame._slFadeOut = ag
        frame._slFadeOutAnim = anim
        anim:SetSmoothing("OUT")
    end

    -- 진행 중인 FadeIn 중지
    if frame._slFadeIn and frame._slFadeIn:IsPlaying() then
        frame._slFadeIn:Stop()
    end

    local ag = frame._slFadeOut
    local anim = frame._slFadeOutAnim

    anim:SetDuration(duration)
    anim:SetFromAlpha(startAlpha)
    anim:SetToAlpha(endAlpha)

    ag:SetScript("OnFinished", function()
        frame:SetAlpha(endAlpha)
        if hideOnFinish then frame:Hide() end
        if onFinish then onFinish(frame) end
    end)

    frame:SetAlpha(startAlpha)
    ag:Play()
end

---------------------------------------------------------------------
-- SlideIn / SlideOut
---------------------------------------------------------------------

--- 프레임을 슬라이드하며 나타나게 합니다.
--- @param frame Frame
--- @param direction string  "UP"|"DOWN"|"LEFT"|"RIGHT"
--- @param distance number  슬라이드 거리 (px)
--- @param duration number|nil  기본 0.25초
--- @param onFinish function|nil
function Lib.SlideIn(frame, direction, distance, duration, onFinish)
    duration = duration or 0.25

    if not frame._slSlideIn then
        local ag = frame:CreateAnimationGroup()
        local move = ag:CreateAnimation("Translation")
        local fade = ag:CreateAnimation("Alpha")
        frame._slSlideIn = ag
        frame._slSlideInMove = move
        frame._slSlideInFade = fade
        move:SetSmoothing("OUT")
        fade:SetSmoothing("IN")
    end

    if frame._slSlideOut and frame._slSlideOut:IsPlaying() then
        frame._slSlideOut:Stop()
    end

    local ag = frame._slSlideIn
    local move = frame._slSlideInMove
    local fade = frame._slSlideInFade

    local dx, dy = 0, 0
    if direction == "UP" then dy = -distance
    elseif direction == "DOWN" then dy = distance
    elseif direction == "LEFT" then dx = distance
    elseif direction == "RIGHT" then dx = -distance
    end

    move:SetDuration(duration)
    move:SetOffset(dx, dy)
    fade:SetDuration(duration * 0.6)
    fade:SetFromAlpha(0)
    fade:SetToAlpha(1)
    fade:SetStartDelay(0)

    ag:SetScript("OnFinished", function()
        frame:SetAlpha(1)
        if onFinish then onFinish(frame) end
    end)

    frame:SetAlpha(0)
    frame:Show()
    ag:Play()
end

--- 프레임을 슬라이드하며 사라지게 합니다.
--- @param frame Frame
--- @param direction string  "UP"|"DOWN"|"LEFT"|"RIGHT"
--- @param distance number
--- @param duration number|nil
--- @param hideOnFinish boolean|nil  기본 true
--- @param onFinish function|nil
function Lib.SlideOut(frame, direction, distance, duration, hideOnFinish, onFinish)
    duration = duration or 0.25
    if hideOnFinish == nil then hideOnFinish = true end

    if not frame._slSlideOut then
        local ag = frame:CreateAnimationGroup()
        local move = ag:CreateAnimation("Translation")
        local fade = ag:CreateAnimation("Alpha")
        frame._slSlideOut = ag
        frame._slSlideOutMove = move
        frame._slSlideOutFade = fade
        move:SetSmoothing("IN")
        fade:SetSmoothing("OUT")
    end

    if frame._slSlideIn and frame._slSlideIn:IsPlaying() then
        frame._slSlideIn:Stop()
    end

    local ag = frame._slSlideOut
    local move = frame._slSlideOutMove
    local fade = frame._slSlideOutFade

    local dx, dy = 0, 0
    if direction == "UP" then dy = distance
    elseif direction == "DOWN" then dy = -distance
    elseif direction == "LEFT" then dx = -distance
    elseif direction == "RIGHT" then dx = distance
    end

    move:SetDuration(duration)
    move:SetOffset(dx, dy)
    fade:SetDuration(duration)
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)

    ag:SetScript("OnFinished", function()
        frame:SetAlpha(0)
        if hideOnFinish then frame:Hide() end
        frame:SetAlpha(1) -- restore for next show
        if onFinish then onFinish(frame) end
    end)

    ag:Play()
end

---------------------------------------------------------------------
-- Pulse (반복 페이드)
---------------------------------------------------------------------

--- 프레임을 반복적으로 깜빡이게 합니다.
--- @param frame Frame
--- @param duration number|nil  1사이클 기본 0.8초
--- @param minAlpha number|nil  기본 0.3
--- @param maxAlpha number|nil  기본 1
function Lib.StartPulse(frame, duration, minAlpha, maxAlpha)
    duration = duration or 0.8
    minAlpha = minAlpha or 0.3
    maxAlpha = maxAlpha or 1

    if not frame._slPulse then
        local ag = frame:CreateAnimationGroup()
        ag:SetLooping("BOUNCE")
        local anim = ag:CreateAnimation("Alpha")
        anim:SetSmoothing("IN_OUT")
        frame._slPulse = ag
        frame._slPulseAnim = anim
    end

    local anim = frame._slPulseAnim
    anim:SetDuration(duration / 2) -- BOUNCE이므로 절반
    anim:SetFromAlpha(maxAlpha)
    anim:SetToAlpha(minAlpha)

    frame:SetAlpha(maxAlpha)
    frame._slPulse:Play()
end

function Lib.StopPulse(frame)
    if frame._slPulse and frame._slPulse:IsPlaying() then
        frame._slPulse:Stop()
        frame:SetAlpha(1)
    end
end

---------------------------------------------------------------------
-- Flash (N회 깜빡)
---------------------------------------------------------------------

--- 프레임을 N회 깜빡이게 합니다.
--- @param frame Frame
--- @param count number|nil  기본 3회
--- @param duration number|nil  1사이클 기본 0.3초
--- @param onFinish function|nil
function Lib.Flash(frame, count, duration, onFinish)
    count = count or 3
    duration = duration or 0.3

    if not frame._slFlash then
        local ag = frame:CreateAnimationGroup()
        ag:SetLooping("BOUNCE")
        local anim = ag:CreateAnimation("Alpha")
        anim:SetSmoothing("IN_OUT")
        frame._slFlash = ag
        frame._slFlashAnim = anim
    end

    local ag = frame._slFlash
    local anim = frame._slFlashAnim
    local cycles = 0
    local maxCycles = count * 2 -- BOUNCE는 2배

    anim:SetDuration(duration / 2)
    anim:SetFromAlpha(1)
    anim:SetToAlpha(0.1)

    ag:SetLooping("BOUNCE")
    ag:SetScript("OnLoop", function()
        cycles = cycles + 1
        if cycles >= maxCycles then
            ag:Stop()
            frame:SetAlpha(1)
            if onFinish then onFinish(frame) end
        end
    end)

    frame:SetAlpha(1)
    ag:Play()
end

---------------------------------------------------------------------
-- Smooth Size Change
---------------------------------------------------------------------

--- 프레임 크기를 부드럽게 변경합니다 (OnUpdate 기반)
--- @param frame Frame
--- @param targetWidth number
--- @param targetHeight number
--- @param duration number|nil  기본 0.2초
--- @param onFinish function|nil
function Lib.SmoothResize(frame, targetWidth, targetHeight, duration, onFinish)
    duration = duration or 0.2

    local startWidth = frame:GetWidth()
    local startHeight = frame:GetHeight()
    local elapsed = 0

    frame:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        local progress = elapsed / duration
        if progress >= 1 then
            progress = 1
            self:SetScript("OnUpdate", nil)
            if onFinish then onFinish(self) end
        end
        -- ease out quad
        local t = 1 - (1 - progress) * (1 - progress)
        self:SetSize(
            startWidth + (targetWidth - startWidth) * t,
            startHeight + (targetHeight - startHeight) * t
        )
    end)
end
