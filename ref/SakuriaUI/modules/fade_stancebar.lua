local stanceFaded = false
local FADE_IN_DUR   = 0.2
local FADE_OUT_DUR  = 0.4
local LEAVE_DELAY   = 0.2

local function SafeSetMouse(frame, enabled)
    if InCombatLockdown() or not frame then return end
    frame:EnableMouse(enabled)
end

local function FadeStance(frame, show)
    if not frame then return end
    local current = frame:GetAlpha() or 1
    local target  = show and 1 or 0
    if current == target then return end

    if InCombatLockdown() then
        frame:SetAlpha(target)
        return
    end

    if show then
        UIFrameFadeIn(frame, FADE_IN_DUR, current, 1)
        SafeSetMouse(frame, true)
    else
        UIFrameFadeOut(frame, FADE_OUT_DUR, current, 0)
        C_Timer.After(FADE_OUT_DUR, function()
            SafeSetMouse(frame, false)
        end)
    end
end

function SakuriaUI_EnableFadeStanceBar()
    local stanceBar = StanceBar
    if not stanceBar or stanceFaded then return end
    stanceFaded = true

    for i = 1, 10 do
        local btn = _G["StanceButton"..i]
        if btn then
            btn:HookScript("OnEnter", function() FadeStance(stanceBar, true) end)
            btn:HookScript("OnLeave", function()
                C_Timer.After(LEAVE_DELAY, function()
                    if not stanceBar:IsMouseOver() then
                        FadeStance(stanceBar, false)
                    end
                end)
            end)
        end
    end

    stanceBar:HookScript("OnEnter", function() FadeStance(stanceBar, true) end)
    stanceBar:HookScript("OnLeave", function()
        C_Timer.After(LEAVE_DELAY, function()
            if not stanceBar:IsMouseOver() then
                FadeStance(stanceBar, false)
            end
        end)
    end)

    FadeStance(stanceBar, false)
    if not InCombatLockdown() then stanceBar:EnableMouse(false) end

    if not SakuriaUI_FadeStanceFrame then
        local f = CreateFrame("Frame")
        f:RegisterEvent("PLAYER_REGEN_ENABLED")
        f:SetScript("OnEvent", function()
            if stanceBar:IsMouseOver() then
                FadeStance(stanceBar, true)
                SafeSetMouse(stanceBar, true)
            else
                FadeStance(stanceBar, false)
                SafeSetMouse(stanceBar, false)
            end
        end)
        SakuriaUI_FadeStanceFrame = f
    end
end

function SakuriaUI_DisableFadeStanceBar()
    local stanceBar = StanceBar
    if not stanceBar then return end
    stanceBar:SetAlpha(1)
    SafeSetMouse(stanceBar, true)
end