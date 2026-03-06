local petFaded = false
local PET_FADE_IN_DUR   = 0.2
local PET_FADE_OUT_DUR  = 0.4
local PET_LEAVE_DELAY   = 0.2

local function PetSafeSetMouse(frame, enabled)
    if InCombatLockdown() or not frame then return end
    frame:EnableMouse(enabled)
end

local function ForEachPetContainer(fn)
    local parent = PetActionBarButtonContainer
    if parent then
        fn(parent)
        return
    end

    for i = 1, 10 do
        local c = _G["PetActionBarButtonContainer"..i]
        if c then fn(c) end
    end
end

local function FadePet(show)
    ForEachPetContainer(function(frame)
        if not frame or not frame:IsShown() then return end

        local current = frame:GetAlpha() or 1
        local target  = show and 1 or 0
        if current == target then return end

        if InCombatLockdown() then
            frame:SetAlpha(target)
            return
        end

        if show then
            UIFrameFadeIn(frame, PET_FADE_IN_DUR, current, 1)
            PetSafeSetMouse(frame, true)
        else
            UIFrameFadeOut(frame, PET_FADE_OUT_DUR, current, 0)
            C_Timer.After(PET_FADE_OUT_DUR, function()
                PetSafeSetMouse(frame, false)
            end)
        end
    end)
end

function SakuriaUI_EnableFadePetBar()
    if petFaded then return end
    petFaded = true

    for i = 1, 10 do
        local btn = _G["PetActionButton"..i]
        if btn and not btn.__sakuPetHooked then
            btn.__sakuPetHooked = true

            btn:HookScript("OnEnter", function()
                FadePet(true)
            end)

            btn:HookScript("OnLeave", function()
                C_Timer.After(PET_LEAVE_DELAY, function()
                    local hovered = false
                    ForEachPetContainer(function(frame)
                        if frame and frame:IsShown() and frame:IsMouseOver() then
                            hovered = true
                        end
                    end)
                    if not hovered then
                        FadePet(false)
                    end
                end)
            end)
        end
    end

    C_Timer.After(0.1, function()
        FadePet(false)
        ForEachPetContainer(function(frame)
            if frame and frame:IsShown() and not InCombatLockdown() then
                frame:EnableMouse(false)
            end
        end)
    end)

    if not SakuriaUI_FadePetFrame then
        local ef = CreateFrame("Frame")
        ef:RegisterEvent("PET_BAR_UPDATE")
        ef:RegisterEvent("UNIT_PET")
        ef:RegisterEvent("PLAYER_ENTERING_WORLD")
        ef:SetScript("OnEvent", function(_, event, unit)
            if event == "UNIT_PET" and unit ~= "player" then return end
            FadePet(false)
        end)
        SakuriaUI_FadePetFrame = ef
    end
end

function SakuriaUI_DisableFadePetBar()
    ForEachPetContainer(function(frame)
        if frame then
            frame:SetAlpha(1)
            PetSafeSetMouse(frame, true)
        end
    end)
end