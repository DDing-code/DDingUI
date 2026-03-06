local ADDON_NAME = "SakuriaUI"

local hooked = {}

local COOLDOWN_STYLE = {
    showSwipe = true,
    showEdge  = false,
    showBling = true,
    reverse   = false,
    swipeRGBA = { 0, 0, 0, 0.7 },
}

local VIEWERS = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
}

local function ApplyCooldownStyle(cd)
    local s = COOLDOWN_STYLE
    cd:SetDrawSwipe(s.showSwipe)
    cd:SetDrawEdge(s.showEdge)
    cd:SetDrawBling(s.showBling)
    cd:SetReverse(s.reverse)

    local c = s.swipeRGBA
    if c then
        cd:SetSwipeColor(c[1], c[2], c[3], c[4])
    end
end

local function GetSpellID(frame)
    local info = frame and frame.cooldownInfo
    return info and (info.overrideSpellID or info.spellID)
end

local function ClearCooldown(cd)
    if cd and cd.Clear then
        cd:Clear()
    end
end

-- Some spells (like Burning Rush) return a table even when no cooldown is actually running
-- Only apply charge cooldowns if there's an actual cooldown running
local function TryApplyChargeCooldown(cd, spellID)
    if not (C_Spell and C_Spell.GetSpellCharges) then return false end

    local chargeInfo = C_Spell.GetSpellCharges(spellID)
    if not chargeInfo then return false end

    -- Only use non-table duration objects
    if type(chargeInfo) ~= "table" and cd.SetCooldownFromDurationObject then
        local success = pcall(function()
            cd:SetCooldownFromDurationObject(chargeInfo, false)
        end)
        if success then
            return true
        end
    end

    -- If it's a charged spell & we can't get the values, mark as handled
    if type(chargeInfo) == "table" then
        return true
    end

    return false
end

local function SetCooldownForSpell(cd, spellID)
    if not cd or not spellID or spellID == 0 then
        ClearCooldown(cd)
        return
    end

    -- Charges (only if an actual cooldown is running)
    if TryApplyChargeCooldown(cd, spellID) then
        return
    end

    if cd.SetCooldownFromDurationObject and C_Spell and C_Spell.GetSpellCooldownDuration then
        local durationObj = C_Spell.GetSpellCooldownDuration(spellID)
        if durationObj then
            cd:SetCooldownFromDurationObject(durationObj, false)
            return
        end
    end

    if C_Spell and C_Spell.GetSpellCooldown then
        local success = pcall(function()
            local info = C_Spell.GetSpellCooldown(spellID)
            if info and info.startTime and info.duration then
                cd:SetCooldown(info.startTime, info.duration)
            end
        end)
        if success then
            return
        end
    end

    ClearCooldown(cd)
end

local function UpdateCooldownFrame(cd)
    if cd.sakuBypassHook then return end

    local parent = cd.sakuParentFrame
    if not parent or not parent.cooldownInfo then return end

    local spellID = GetSpellID(parent)
    if not spellID then return end

    cd.sakuBypassHook = true
    SetCooldownForSpell(cd, spellID)
    ApplyCooldownStyle(cd)
    cd.sakuBypassHook = false
end

local function HookCooldownFrame(cd, parent)
    if not cd or hooked[cd] then return end
    if not parent or not parent.cooldownInfo then return end

    hooked[cd] = true
    cd.sakuParentFrame = parent
    cd.sakuBypassHook = false

    hooksecurefunc(cd, "SetCooldown", UpdateCooldownFrame)

    if cd.SetCooldownFromDurationObject then
        hooksecurefunc(cd, "SetCooldownFromDurationObject", UpdateCooldownFrame)
    end
end

local function ScanCooldownFrames()
    local count = 0

    for _, viewerName in ipairs(VIEWERS) do
        local viewer = _G[viewerName]
        if viewer then
            for _, child in ipairs({ viewer:GetChildren() }) do
                if child and child.Cooldown and child.cooldownInfo then
                    HookCooldownFrame(child.Cooldown, child)
                    count = count + 1
                end
            end
        end
    end

    if count > 0 then
        -- print(string.format("|cffff7f7f[%s]|r Cooldown overlay removed (%d frames)", ADDON_NAME, count))
    end
end

local Cooldowns = {}

local eventFrame
local function EnsureEventFrame()
    if eventFrame then return end
    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", function(_, _, addon)
        if addon == "Blizzard_CooldownViewer" then
            C_Timer.After(0.5, ScanCooldownFrames)
        end
    end)
end

function Cooldowns:Enable()
    hooked = {}
    ScanCooldownFrames()
    EnsureEventFrame()
    eventFrame:UnregisterAllEvents()
    eventFrame:RegisterEvent("ADDON_LOADED")
end

function Cooldowns:Disable()
    hooked = {}

    if eventFrame then
        eventFrame:UnregisterAllEvents()
    end
end

SakuriaUI_DisableAuraOverlay = Cooldowns