SakuriaUI_Crosshair = SakuriaUI_Crosshair or {}

local SIZE  = 22
local THICK = 6
local ALPHA = 1

local COLOR_R, COLOR_G, COLOR_B = 0.1, 1.0, 0.1
local OFFSET_X, OFFSET_Y = 0, -30

local cross
local enabled = false

local function EnsureFrame()
    if cross then return end

    cross = CreateFrame("Frame", "SakuriaCrosshairFrame", UIParent)
    cross:SetSize(SIZE, SIZE)
    cross:SetPoint("CENTER", UIParent, "CENTER", OFFSET_X, OFFSET_Y)
    cross:EnableMouse(false)
    cross:SetFrameStrata("TOOLTIP")
    cross:SetFrameLevel(999)
    cross:Hide()

    local function MakeLine(parent, w, h)
        local t = parent:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(COLOR_R, COLOR_G, COLOR_B, 1)
        t:SetSize(w, h)
        t:SetPoint("CENTER", parent, "CENTER", 0, 0)
        t:SetAlpha(ALPHA)
        return t
    end

    MakeLine(cross, SIZE, THICK)
    MakeLine(cross, THICK, SIZE)

    local function Update()
        if not enabled then
            cross:Hide()
            return
        end

        if UnitAffectingCombat("player") then
            cross:Show()
        else
            cross:Hide()
        end
    end

    cross:RegisterEvent("PLAYER_ENTERING_WORLD")
    cross:RegisterEvent("PLAYER_REGEN_DISABLED")
    cross:RegisterEvent("PLAYER_REGEN_ENABLED")
    cross:SetScript("OnEvent", Update)

    cross._Sakuria_Update = Update
end

function SakuriaUI_Crosshair.Enable()
    EnsureFrame()
    enabled = true
    if cross and cross._Sakuria_Update then
        cross._Sakuria_Update()
    end
end

function SakuriaUI_Crosshair.Disable()
    enabled = false
    if cross then
        cross:Hide()
    end
end