local FADE_IN   = 0.15
local FADE_OUT  = 0.30
local LEAVE_DELAY = 0.20

local proxy
local enabled = false

local function Menu()
    return MicroMenuContainer
end

local function Fade(menu, toAlpha, dur)
    if not menu then return end
    UIFrameFadeRemoveFrame(menu)

    local from = menu:GetAlpha() or 1
    if toAlpha > from then
        UIFrameFadeIn(menu, dur, from, toAlpha)
    else
        UIFrameFadeOut(menu, dur, from, toAlpha)
    end
end

local function SetInteractive(menu, on)
    if not menu then return end
    menu:EnableMouse(on)

    -- Can't accidentally click through while hidden
    for _, child in ipairs({ menu:GetChildren() }) do
        if child and child.EnableMouse then
            child:EnableMouse(on)
        end
    end
end

local function SetProxyLevel(menu, above)
    if not proxy or not menu then return end
    if above then
        proxy:SetFrameLevel(menu:GetFrameLevel() + 50)
    else
        local lvl = menu:GetFrameLevel() - 1
        if lvl < 0 then lvl = 0 end
        proxy:SetFrameLevel(lvl)
    end
end

local function PositionProxy(menu)
    if not proxy or not menu then return end
    proxy:ClearAllPoints()
    proxy:SetAllPoints(menu)
    proxy:SetFrameStrata(menu:GetFrameStrata())
end

local function ShouldHide(menu)
    if not enabled or not menu or not proxy then return false end
    if proxy:IsMouseOver() then return false end
    if menu:IsMouseOver() then return false end
    return true
end

local function Show(menu)
    if not menu then return end
    menu:Show()
    Fade(menu, 1, FADE_IN)
    SetInteractive(menu, true)
    SetProxyLevel(menu, false)
end

local function Hide(menu)
    if not menu then return end
    Fade(menu, 0, FADE_OUT)
    SetInteractive(menu, false)
    SetProxyLevel(menu, true)
end

local function EnsureProxy(menu)
    if proxy then return end

    proxy = CreateFrame("Frame", nil, UIParent)
    proxy:SetAlpha(0)
    proxy:EnableMouse(true)

    proxy:SetScript("OnEnter", function()
        local m = Menu()
        if enabled and m then
            Show(m)
        end
    end)

    proxy:SetScript("OnLeave", function()
        C_Timer.After(LEAVE_DELAY, function()
            local m = Menu()
            if enabled and m and ShouldHide(m) then
                Hide(m)
            end
        end)
    end)
end

local function HookChildrenForLeave(menu)
    if not menu or menu.__SakuriaUI_MenuFaderHooked then return end
    menu.__SakuriaUI_MenuFaderHooked = true

    local function delayedHide()
        C_Timer.After(LEAVE_DELAY, function()
            if enabled and ShouldHide(menu) then
                Hide(menu)
            end
        end)
    end

    menu:HookScript("OnLeave", delayedHide)

    for _, child in ipairs({ menu:GetChildren() }) do
        if child and child.HookScript and not child.__SakuriaUI_MenuFaderHookedChild then
            child.__SakuriaUI_MenuFaderHookedChild = true
            child:HookScript("OnLeave", delayedHide)
        end
    end
end

SakuriaUI_HideMenu = {
    Enable = function()
        local menu = Menu()
        if not menu then return end
        enabled = true

        EnsureProxy(menu)
        HookChildrenForLeave(menu)
        PositionProxy(menu)
        Hide(menu)

        if not SakuriaUI_MenuProxyUpdater then
            local u = CreateFrame("Frame")
            u:RegisterEvent("PLAYER_ENTERING_WORLD")
            u:RegisterEvent("UI_SCALE_CHANGED")
            u:RegisterEvent("DISPLAY_SIZE_CHANGED")
            u:SetScript("OnEvent", function()
                local m = Menu()
                if enabled and proxy and m then
                    PositionProxy(m)
                    if (m:GetAlpha() or 0) > 0.01 then
                        SetProxyLevel(m, false)
                    else
                        SetProxyLevel(m, true)
                    end
                end
            end)
            SakuriaUI_MenuProxyUpdater = u
        end
    end,

    Disable = function()
        local menu = Menu()
        enabled = false

        if menu then
            UIFrameFadeRemoveFrame(menu)
            menu:SetAlpha(1)
            menu:Show()
            SetInteractive(menu, true)
        end

        if proxy then
            proxy:EnableMouse(false)
            proxy:Hide()
        end
    end,
}