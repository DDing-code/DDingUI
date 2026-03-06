----------------------------------------------------------------------
-- DDingUI Nameplate - Auras.lua
-- Debuff/buff display with icon pooling and filtering
----------------------------------------------------------------------
local ADDON_NAME, ns = ...

local FLAT = ns.FLAT
local FONT = ns.FONT

----------------------------------------------------------------------
-- Icon pool -- [NAMEPLATE]
----------------------------------------------------------------------
local iconPool = {}

local function AcquireIcon(parent)
    local icon = tremove(iconPool)
    if icon then
        icon:SetParent(parent)
        icon:ClearAllPoints()
        icon:Show()
        return icon
    end

    -- Create new icon frame -- [NAMEPLATE]
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(20, 20)

    -- Icon texture
    local tex = frame:CreateTexture(nil, "ARTWORK")
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    tex:SetAllPoints(frame)
    frame.icon = tex

    -- Border
    local border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    border:SetBackdrop({ edgeFile = FLAT, edgeSize = 1 })
    local borderColor = ns.GetSLColor("border.default")
    border:SetBackdropBorderColor(ns.UnpackColor(borderColor))
    border:SetPoint("TOPLEFT", frame, "TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 1, -1)
    border:SetFrameLevel(frame:GetFrameLevel() + 1)
    frame.border = border

    -- Cooldown spiral
    local cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cooldown:SetAllPoints(frame)
    cooldown:SetDrawEdge(false)
    cooldown:SetHideCountdownNumbers(true)
    frame.cooldown = cooldown

    -- Stack count
    local stack = frame:CreateFontString(nil, "OVERLAY")
    stack:SetFont(FONT, 9, "OUTLINE")
    stack:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 1, -1)
    stack:SetJustifyH("RIGHT")
    stack:SetTextColor(1, 1, 1)
    frame.stack = stack

    return frame
end

local function ReleaseIcon(icon)
    icon:Hide()
    icon:SetParent(nil)
    icon:ClearAllPoints()
    if icon.cooldown then icon.cooldown:Clear() end
    if icon.stack then icon.stack:SetText("") end
    tinsert(iconPool, icon)
end

----------------------------------------------------------------------
-- Create aura container frame -- [NAMEPLATE]
----------------------------------------------------------------------
function ns.CreateAuraFrame(data)
    local parent = data.frame

    local auraFrame = CreateFrame("Frame", nil, parent)
    auraFrame:SetSize(1, 1)  -- Dynamic size
    auraFrame:SetFrameLevel(parent:GetFrameLevel() + 4)

    data.auraFrame   = auraFrame
    data.auraIcons   = {}  -- Currently shown icons
end

----------------------------------------------------------------------
-- Hide all auras -- [NAMEPLATE]
----------------------------------------------------------------------
function ns.HideAllAuras(data)
    if not data.auraIcons then return end
    for i = #data.auraIcons, 1, -1 do
        ReleaseIcon(data.auraIcons[i])
        data.auraIcons[i] = nil
    end
end

----------------------------------------------------------------------
-- UpdateAuras -- [NAMEPLATE]
-- Uses C_UnitAuras API for modern WoW (12.x)
----------------------------------------------------------------------
function ns.UpdateAuras(data, unitID)
    if not data.auraFrame or not unitID then return end

    local db = ns.db.auras
    if not db.enabled then
        ns.HideAllAuras(data)
        return
    end

    -- [PERF] 아우라 fingerprint diff — spellID 조합이 안 바뀌면 아이콘 재배치 스킵
    local maxAuras = db.maxAuras or 5
    local iconSize = db.iconSize or 20
    local spacing  = db.spacing or 2

    -- fingerprint 수집 (spellID 목록)
    local newFingerprint = ""
    local fpCount = 0
    local function BuildFingerprint(auraData)
        if not auraData then return false end
        if fpCount >= maxAuras then return false end
        if db.myDebuffsOnly and not auraData.isFromPlayerOrPlayerPet then return true end
        if data.isFriendly then return true end
        if not auraData.isHarmful then return true end
        fpCount = fpCount + 1
        local stk = auraData.applications or 0
        if issecretvalue and issecretvalue(stk) then stk = 0 end
        newFingerprint = newFingerprint .. (auraData.spellId or 0) .. ":" .. stk .. ","
        return true
    end
    if AuraUtil and AuraUtil.ForEachAura then
        AuraUtil.ForEachAura(unitID, "HARMFUL", maxAuras, BuildFingerprint, true)
    else
        for i = 1, 40 do
            local ad = C_UnitAuras.GetAuraDataByIndex(unitID, i, "HARMFUL")
            if not ad then break end
            if not BuildFingerprint(ad) then break end
        end
    end

    -- fingerprint 동일하면 아이콘 갱신 불필요
    if data._auraFingerprint == newFingerprint and #data.auraIcons > 0 then
        return
    end
    data._auraFingerprint = newFingerprint

    -- Clear existing icons
    ns.HideAllAuras(data)

    -- Collect auras using AuraUtil or direct iteration -- [NAMEPLATE]
    local count = 0

    -- Use UnitAuraSlots/GetAuraDataBySlot (modern API) -- [NAMEPLATE]
    local function ProcessAura(auraData)
        if not auraData then return false end
        if count >= maxAuras then return false end

        -- Filter: my debuffs only
        if db.myDebuffsOnly then
            if not auraData.isFromPlayerOrPlayerPet then
                return true  -- skip but continue
            end
        end

        -- Only harmful (debuffs) on enemy plates
        if data.isFriendly then return true end
        if not auraData.isHarmful then return true end

        count = count + 1

        -- Create/acquire icon
        local icon = AcquireIcon(data.auraFrame)
        icon:SetSize(iconSize, iconSize)

        -- Texture
        if auraData.icon then
            icon.icon:SetTexture(auraData.icon)
        end

        -- Cooldown spiral -- [NAMEPLATE]
        if db.showCooldown and auraData.duration and auraData.duration > 0
            and auraData.expirationTime and auraData.expirationTime > 0 then
            icon.cooldown:SetCooldown(
                auraData.expirationTime - auraData.duration,
                auraData.duration
            )
        else
            icon.cooldown:Clear()
        end

        -- Stack count
        if db.showStacks and auraData.applications and auraData.applications > 1 then
            -- Secret value protection -- [NAMEPLATE]
            local stacks = auraData.applications
            if issecretvalue and issecretvalue(stacks) then
                icon.stack:SetText("")
            else
                icon.stack:SetText(tostring(stacks))
            end
        else
            icon.stack:SetText("")
        end

        -- Position
        local idx = count - 1
        icon:ClearAllPoints()
        icon:SetPoint("LEFT", data.auraFrame, "LEFT", idx * (iconSize + spacing), 0)

        tinsert(data.auraIcons, icon)
        return true
    end

    -- Iterate using ForEachAura (modern API, 12.x safe) -- [NAMEPLATE]
    if AuraUtil and AuraUtil.ForEachAura then
        AuraUtil.ForEachAura(unitID, "HARMFUL", maxAuras, function(auraData)
            return ProcessAura(auraData)
        end, true)  -- usePackedAura = true
    else
        -- Fallback: manual iteration
        for i = 1, 40 do
            local auraData = C_UnitAuras.GetAuraDataByIndex(unitID, i, "HARMFUL")
            if not auraData then break end
            if not ProcessAura(auraData) then break end
        end
    end

    -- Position aura frame below cast bar or health bar -- [NAMEPLATE]
    data.auraFrame:ClearAllPoints()
    local anchor
    if data.castBar and data.castBar.frame and data.castBar.frame:IsShown() then
        anchor = data.castBar.frame
    elseif data.healthBar and data.healthBar.bar then
        anchor = data.healthBar.bar
    else
        anchor = data.frame
    end

    -- Center the aura row
    local totalWidth = count * (iconSize + spacing) - spacing
    if totalWidth < 0 then totalWidth = 0 end
    data.auraFrame:SetSize(totalWidth, iconSize)
    data.auraFrame:SetPoint("TOP", anchor, "BOTTOM", 0, -3)
end
