local fadedBars = {}

local BAR_CONFIG = {
    { key = "MainActionBar",        frame = MainActionBar,        prefix = "Action" },
    { key = "MultiBarBottomLeft",   frame = MultiBarBottomLeft,   prefix = "MultiBarBottomLeft" },
    { key = "MultiBarBottomRight",  frame = MultiBarBottomRight,  prefix = "MultiBarBottomRight" },
    { key = "MultiBarRight",        frame = MultiBarRight,        prefix = "MultiBarRight" },
    { key = "MultiBarLeft",         frame = MultiBarLeft,         prefix = "MultiBarLeft" },
    { key = "MultiBar5",            frame = MultiBar5,            prefix = "MultiBar5" },
    { key = "MultiBar6",            frame = MultiBar6,            prefix = "MultiBar6" },
    { key = "MultiBar7",            frame = MultiBar7,            prefix = "MultiBar7" },
}

local FADE_IN_DUR   = 0.2
local FADE_OUT_DUR  = 0.4
local LEAVE_DELAY   = 0.2

local function SafeSetMouse(frame, enabled)
    if InCombatLockdown() or not frame then return end
    frame:EnableMouse(enabled)
end

local function FadeFrame(frame, show)
    if not frame then return end
    if not frame:IsShown() then
        return
    end

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

local function HookBar(frame, prefix)
    if not frame or fadedBars[frame] then return end

    if not frame:IsShown() then
        return
    end

    for i = 1, 12 do
        local btn = _G[prefix .. "Button" .. i]
        if btn then
            btn:HookScript("OnEnter", function() FadeFrame(frame, true) end)
            btn:HookScript("OnLeave", function()
                C_Timer.After(LEAVE_DELAY, function()
                    if not btn:IsMouseOver() and not frame:IsMouseOver() then
                        FadeFrame(frame, false)
                    end
                end)
            end)
        end
    end

    frame:HookScript("OnEnter", function() FadeFrame(frame, true) end)
    frame:HookScript("OnLeave", function()
        C_Timer.After(LEAVE_DELAY, function()
            if not frame:IsMouseOver() then
                FadeFrame(frame, false)
            end
        end)
    end)

    FadeFrame(frame, false)
    if not InCombatLockdown() then frame:EnableMouse(false) end

    fadedBars[frame] = true
end

local function BarEnabled(key)
    if not SakuriaUI_DB or not SakuriaUI_DB.fadeBars then
        return true
    end
    return SakuriaUI_DB.fadeBars[key] ~= false
end

function SakuriaUI_EnableFadeActionBars()
    for _, bar in ipairs(BAR_CONFIG) do
        if bar.frame then
		
            if not bar.frame:IsShown() then
                SafeSetMouse(bar.frame, true)
            else
                if BarEnabled(bar.key) then
                    HookBar(bar.frame, bar.prefix)
                else
                    bar.frame:SetAlpha(1)
                    SafeSetMouse(bar.frame, true)
                end
            end
        end
    end

    if not SakuriaUI_FadeBarsFrame then
        local f = CreateFrame("Frame")
        f:RegisterEvent("PLAYER_REGEN_ENABLED")
        f:SetScript("OnEvent", function()
            for frame in pairs(fadedBars) do
                if frame:IsShown() then
                    if frame:IsMouseOver() then
                        FadeFrame(frame, true)
                        SafeSetMouse(frame, true)
                    else
                        FadeFrame(frame, false)
                        SafeSetMouse(frame, false)
                    end
                end
            end
        end)
        SakuriaUI_FadeBarsFrame = f
    end
end

function SakuriaUI_DisableFadeActionBars()
    for frame in pairs(fadedBars) do
	
        if frame and frame:IsShown() then
            frame:SetAlpha(1)
            SafeSetMouse(frame, true)
        end
    end
    fadedBars = {}
end