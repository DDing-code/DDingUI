local ADDON_NAME, ns = ...
local DDingUI = ns.Addon

-- Get CastBars module
local CastBars = DDingUI.CastBars
if not CastBars then
    error("DDingUI: CastBars module not initialized! Load CastBars.lua first.")
end

local CastBar_OnUpdate = CastBars.CastBar_OnUpdate
local CreateBorder = CastBars.CreateBorder
local GetClassColor = CastBars.GetClassColor

-- Weak table to track disabled state without tainting Blizzard frames
local castBarState = setmetatable({}, { __mode = "k" })

-- Use shared PixelSnap from Toolkit
local PixelSnap = DDingUI.PixelSnapLocal or function(value)
    return math.max(0, math.floor((value or 0) + 0.5))
end

-- PLAYER CAST BAR

function CastBars:GetCastBar()
    if DDingUI.castBar then return DDingUI.castBar end

    local cfg    = DDingUI.db.profile.castBar
    local anchor = _G[cfg.attachTo] or UIParent
    local anchorPoint = cfg.anchorPoint or "CENTER"



    local bar = CreateFrame("Frame", ADDON_NAME .. "CastBar", anchor)
    bar:SetFrameStrata(cfg.frameStrata or "MEDIUM")

    local height = cfg.height or 10
    bar:SetHeight(DDingUI:Scale(height))
    bar:SetPoint("CENTER", anchor, anchorPoint, DDingUI:Scale(cfg.offsetX or 0), DDingUI:Scale(cfg.offsetY or 18))
    -- Use pixel-snapped width from the anchor (but NOT from UIParent or huge frames)
    local initWidth
    local effectiveW = DDingUI:GetEffectiveAnchorWidth(anchor)
    if effectiveW and effectiveW > 0 and effectiveW < 1000 and anchor ~= UIParent then
        initWidth = PixelSnap(effectiveW)
    else
        initWidth = 200
    end
    bar:SetWidth(initWidth)

    CreateBorder(bar)

    -- Status bar
    bar.status = CreateFrame("StatusBar", nil, bar)
    -- Use GetTexture helper: if cfg.texture is set, use it; otherwise use global texture
    local tex = DDingUI:GetTexture(DDingUI.db.profile.castBar.texture)
    bar.status:SetStatusBarTexture(tex)

    local sbTex = bar.status:GetStatusBarTexture()
    if sbTex then
        sbTex:SetDrawLayer("ARTWORK")  -- Draw above segment backgrounds for empowered casts
    end

    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints(bar.status)
    local bgColor = cfg.bgColor or { 0.1, 0.1, 0.1, 1 }
    bar.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)

    bar.icon = bar:CreateTexture(nil, "ARTWORK")
    bar.icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)

    -- Text
    bar.spellName = bar.status:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.spellName:SetJustifyH("LEFT")

    bar.timeText = bar.status:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.timeText:SetJustifyH("RIGHT")

    bar:Hide()

    -- Empowered stages storage
    bar.empoweredStages = {}

    DDingUI.castBar = bar
    return bar
end

-- Events used by Blizzard's CastingBarFrame
local CASTBAR_EVENTS = {
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_INTERRUPTIBLE",
    "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
    "PLAYER_ENTERING_WORLD",
    -- Retail 추가 이벤트
    "UNIT_SPELLCAST_EMPOWER_START",
    "UNIT_SPELLCAST_EMPOWER_UPDATE",
    "UNIT_SPELLCAST_EMPOWER_STOP",
}

function CastBars:UpdateCastBarLayout()
    local cfg = DDingUI.db.profile.castBar

    -- Handle default cast bar visibility using SetUnit (modern approach)
    local defaultCastBar = _G["PlayerCastingBarFrame"] or _G["CastingBarFrame"]
    if defaultCastBar then
        if cfg.enabled then
            -- Custom cast bar is enabled, disable the default one
            if not castBarState[defaultCastBar] then
                -- Guard against modifying protected frames in combat
                if InCombatLockdown() then
                    -- Queue for after combat ends
                    local regenFrame = CreateFrame("Frame")
                    regenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
                    regenFrame:SetScript("OnEvent", function(self)
                        self:UnregisterAllEvents()
                        if not castBarState[defaultCastBar] and cfg.enabled then
                            castBarState[defaultCastBar] = true
                            if defaultCastBar.SetUnit then
                                -- [12.0.1] pcall to avoid forbidden table error in StopFinishAnims
                                local ok = pcall(defaultCastBar.SetUnit, defaultCastBar, nil)
                                if not ok then
                                    defaultCastBar:UnregisterAllEvents()
                                    defaultCastBar:Hide()
                                end
                            else
                                defaultCastBar:UnregisterAllEvents()
                                defaultCastBar:Hide()
                            end
                        end
                    end)
                else
                    castBarState[defaultCastBar] = true
                    -- Use SetUnit(nil) to properly disable (like oUF does)
                    if defaultCastBar.SetUnit then
                        -- [12.0.1] pcall to avoid forbidden table error in StopFinishAnims
                        local ok = pcall(defaultCastBar.SetUnit, defaultCastBar, nil)
                        if not ok then
                            defaultCastBar:UnregisterAllEvents()
                            defaultCastBar:Hide()
                        end
                    else
                        -- Fallback for older API
                        defaultCastBar:UnregisterAllEvents()
                        defaultCastBar:Hide()
                    end
                end
            end
        else
            -- Custom cast bar is disabled, always ensure the default one is enabled
            -- (handles both toggle off and initial load with disabled state)
            castBarState[defaultCastBar] = nil
            -- Guard against modifying protected frames in combat
            if InCombatLockdown() then
                local regenFrame = CreateFrame("Frame")
                regenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
                regenFrame:SetScript("OnEvent", function(self)
                    self:UnregisterAllEvents()
                    if not castBarState[defaultCastBar] then
                        if defaultCastBar.SetUnit then
                            -- [12.0.1] pcall to avoid forbidden table error in StopFinishAnims
                            local ok = pcall(defaultCastBar.SetUnit, defaultCastBar, "player", true, true)
                            if not ok then
                                for _, event in ipairs(CASTBAR_EVENTS) do
                                    pcall(function()
                                        if event == "PLAYER_ENTERING_WORLD" then
                                            defaultCastBar:RegisterEvent(event)
                                        else
                                            defaultCastBar:RegisterUnitEvent(event, "player")
                                        end
                                    end)
                                end
                                defaultCastBar:Show()
                            end
                        else
                            for _, event in ipairs(CASTBAR_EVENTS) do
                                pcall(function()
                                    if event == "PLAYER_ENTERING_WORLD" then
                                        defaultCastBar:RegisterEvent(event)
                                    else
                                        defaultCastBar:RegisterUnitEvent(event, "player")
                                    end
                                end)
                            end
                        end
                        defaultCastBar:SetAlpha(1)
                    end
                end)
            else
                -- Use SetUnit("player") to properly restore/initialize
                if defaultCastBar.SetUnit then
                    -- [12.0.1] pcall to avoid forbidden table error in StopFinishAnims
                    local ok = pcall(defaultCastBar.SetUnit, defaultCastBar, "player", true, true)
                    if not ok then
                        for _, event in ipairs(CASTBAR_EVENTS) do
                            pcall(function()
                                if event == "PLAYER_ENTERING_WORLD" then
                                    defaultCastBar:RegisterEvent(event)
                                else
                                    defaultCastBar:RegisterUnitEvent(event, "player")
                                end
                            end)
                        end
                        defaultCastBar:Show()
                    end
                else
                    -- Fallback: re-register events
                    for _, event in ipairs(CASTBAR_EVENTS) do
                        pcall(function()
                            if event == "PLAYER_ENTERING_WORLD" then
                                defaultCastBar:RegisterEvent(event)
                            else
                                defaultCastBar:RegisterUnitEvent(event, "player")
                            end
                        end)
                    end
                end
                -- Ensure alpha is restored (some addons may set it to 0)
                defaultCastBar:SetAlpha(1)
            end
        end
    end
    
    if not DDingUI.castBar then return end

    local bar    = DDingUI.castBar
    local anchor = _G[cfg.attachTo] or UIParent
    local anchorFallback = false
    if anchor ~= UIParent and not anchor:IsShown() then
        anchor = UIParent
        anchorFallback = true
    end

    -- 앵커 비활성 시 부모 변경 (숨겨진 프레임의 자식은 렌더링되지 않음)
    if anchorFallback then
        if bar:GetParent() ~= UIParent then
            bar:SetParent(UIParent)
        end
    else
        local originalAnchor = _G[cfg.attachTo]
        if originalAnchor and bar:GetParent() ~= originalAnchor then
            bar:SetParent(originalAnchor)
        end
    end

    local anchorPoint, desiredX, desiredY
    if anchorFallback then
        anchorPoint = "CENTER"
        desiredX = 0
        desiredY = 0
    else
        anchorPoint = cfg.anchorPoint or "CENTER"
        desiredX = DDingUI:Scale(cfg.offsetX or 0)
        desiredY = DDingUI:Scale(cfg.offsetY or 18)
    end
    local height = cfg.height or 10

    -- Mover 모드 중에는 위치/크기 재설정 건너뛰기 (드래그와 충돌 방지)
    if not (DDingUI.Movers and DDingUI.Movers.ConfigMode) then
        bar:ClearAllPoints()
        bar:SetPoint("CENTER", anchor, anchorPoint, desiredX, desiredY)
        bar:SetHeight(DDingUI:Scale(height))

        local width = cfg.width or 0
        if width <= 0 then
            -- Auto width: get from viewer or anchor content width
            local effectiveW = DDingUI:GetEffectiveAnchorWidth(anchor)
            if effectiveW and effectiveW > 0 and effectiveW < 1000 and anchor ~= UIParent then
                width = PixelSnap(effectiveW)
            else
                width = 200
            end
            if width <= 0 then
                width = 200
            end
        else
            width = DDingUI:Scale(width)
        end

        bar:SetWidth(width)
    end

    if bar.border then
        bar.border:ClearAllPoints()
        local borderOffset = DDingUI:Scale(1)
        bar.border:SetPoint("TOPLEFT", bar, -borderOffset, borderOffset)
        bar.border:SetPoint("BOTTOMRIGHT", bar, borderOffset, -borderOffset)
    end

    local showIcon = cfg.showIcon ~= false

    -- Icon: left side
    bar.icon:ClearAllPoints()
    if showIcon then
        bar.icon:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
        bar.icon:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
        -- Use bar height directly (already in pixels from SetHeight)
        bar.icon:SetWidth(bar:GetHeight())
        bar.icon:Show()
    else
        bar.icon:SetWidth(0)
        bar.icon:Hide()
    end

    bar.status:ClearAllPoints()
    if showIcon then
        bar.status:SetPoint("TOPLEFT", bar.icon, "TOPRIGHT", 0, 0)
    else
        bar.status:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    end
    bar.status:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)

    bar.bg:ClearAllPoints()
    bar.bg:SetAllPoints(bar.status)

    -- Update background color
    local bgColor = cfg.bgColor or { 0.1, 0.1, 0.1, 1 }
    bar.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)

    -- Use GetTexture helper: if cfg.texture is set, use it; otherwise use global texture
    local tex = DDingUI:GetTexture(cfg.texture)
    bar.status:SetStatusBarTexture(tex)

    local sbTex = bar.status:GetStatusBarTexture()
    if sbTex then
        sbTex:SetDrawLayer("BACKGROUND")
    end

    -- Color
    local r, g, b, a

    if cfg.useClassColor then
        r, g, b = GetClassColor()
        a = 1
    elseif cfg.color then
        r, g, b, a = cfg.color[1], cfg.color[2], cfg.color[3], cfg.color[4] or 1
    else
        r, g, b, a = 1, 0.7, 0, 1
    end

    bar.status:SetStatusBarColor(r, g, b, a or 1)

    bar.spellName:ClearAllPoints()
    bar.spellName:SetPoint("LEFT", bar.status, "LEFT", DDingUI:Scale(4), 0)

    bar.timeText:ClearAllPoints()
    bar.timeText:SetPoint("RIGHT", bar.status, "RIGHT", DDingUI:Scale(-4), 0)

    local font, _, flags = bar.spellName:GetFont()
    bar.spellName:SetFont(font, cfg.textSize or 10, "OUTLINE")
    bar.spellName:SetShadowOffset(0, 0)

    bar.timeText:SetFont(font, cfg.textSize or 10, "OUTLINE")
    bar.timeText:SetShadowOffset(0, 0)
    
    -- Show/hide time text based on setting
    if cfg.showTimeText ~= false then
        bar.timeText:Show()
    else
        bar.timeText:Hide()
    end

    -- Reinitialize empowered stages if bar is currently showing an empowered cast
    if bar.isEmpowered and bar.numStages and bar.numStages > 0 then
        if CastBars.InitializeEmpoweredStages then
            CastBars:InitializeEmpoweredStages(bar)
        end
    end
end

function CastBars:OnPlayerSpellcastStart(unit, castGUID, spellID)
    local cfg = DDingUI.db.profile.castBar
    if not cfg.enabled then
        if DDingUI.castBar then DDingUI.castBar:Hide() end
        return
    end

    -- UnitCastingInfo now returns: name, text, texture, startTimeMS, endTimeMS, isTradeSkill, castID, notInterruptible, spellId, numStages, isEmpowered, castBarID
    -- Regular casts are never empowered - empowered casts come through UnitChannelInfo or UNIT_SPELLCAST_EMPOWER_START
    local name, _, texture, startTimeMS, endTimeMS, isTradeSkill, castID, notInterruptible, unitSpellID, numStages, isEmpowered, castBarID = UnitCastingInfo("player")
    if not name or not startTimeMS or not endTimeMS then
        if DDingUI.castBar then DDingUI.castBar:Hide() end
        return
    end

    local bar = self:GetCastBar()

    -- IMPORTANT: Reset alpha and cancel fade FIRST before anything else
    if bar._ddingFading then
        bar:SetScript("OnUpdate", nil)
        bar._ddingFading = nil
    end
    bar:SetAlpha(1)

    self:UpdateCastBarLayout()

    bar.isChannel = false
    bar.castGUID  = castGUID
    bar.castBarID = castBarID  -- Store castBarID for cast tracking
    
    -- Regular casts are never empowered - don't initialize empowered stages here
    bar.isEmpowered = false
    bar.numStages = 0

    bar.icon:SetTexture(texture)
    bar.spellName:SetText(name)

    local font = DDingUI:GetFont(cfg.textFont)
    bar.spellName:SetFont(font, cfg.textSize or 10, "OUTLINE")
    bar.spellName:SetShadowOffset(0, 0)

    bar.timeText:SetFont(font, cfg.textSize or 10, "OUTLINE")
    bar.timeText:SetShadowOffset(0, 0)

    local now = GetTime()
    bar.startTime = startTimeMS / 1000
    bar.endTime   = endTimeMS / 1000

    -- Safety: if start time is very old, clamp to now
    if bar.startTime < now - 5 then
        local dur = (endTimeMS - startTimeMS) / 1000
        bar.startTime = now
        bar.endTime   = now + dur
    end

    -- Regular casts don't have empowered stages - only channels/empower events do
    -- Clean up any existing empowered stages from previous cast
    if bar.empoweredStages then
        for _, stage in ipairs(bar.empoweredStages) do
            if stage then
                stage:Hide()
                if stage.border then
                    stage.border:Hide()
                end
            end
        end
    end
    if bar.empoweredSegments then
        for _, segment in ipairs(bar.empoweredSegments) do
            if segment then
                segment:Hide()
            end
        end
    end
    if bar.empoweredGlow then
        bar.empoweredGlow:Hide()
    end

    bar:SetScript("OnUpdate", CastBar_OnUpdate)
    bar:Show()
end

function CastBars:OnPlayerSpellcastStop(unit, castGUID, spellID, wasInterrupted)
    local bar = DDingUI.castBar
    if not bar then return end

    -- If a fade animation is in progress, don't interrupt it
    if bar._ddingFading then
        return
    end

    if castGUID and bar.castGUID and castGUID ~= bar.castGUID then
        return
    end

    -- Check if player is still channeling
    if bar.isChannel then
        local name, _, texture, startTimeMS, endTimeMS, isTradeSkill, castID, notInterruptible, unitSpellID, numStages, isEmpowered, castBarID = UnitChannelInfo("player")
        if name and startTimeMS and endTimeMS then
            bar.icon:SetTexture(texture)
            bar.spellName:SetText(name)
            bar.startTime = startTimeMS / 1000
            bar.endTime = endTimeMS / 1000
            bar.castBarID = castBarID
            return
        end
    end

    local cfg = DDingUI.db.profile.castBar

    -- Check if cast was interrupted (ended before completion)
    local isInterrupted = wasInterrupted
    if not isInterrupted and bar.endTime then
        local now = GetTime()
        isInterrupted = (now < bar.endTime - 0.1)
    end

    -- If interrupted, show red color and fade effect
    if isInterrupted and cfg and cfg.interruptedFadeEnabled ~= false then
        -- Mark as fading FIRST (before anything else)
        bar._ddingFading = true

        -- Apply red color
        local color = cfg.interruptedColor or { 0.9, 0.2, 0.2, 1 }
        bar.status:SetStatusBarColor(color[1], color[2], color[3], color[4] or 1)

        -- Fade out using OnUpdate (smoother than C_Timer)
        local fadeDuration = cfg.interruptedFadeDuration or 0.3
        local fadeStartTime = GetTime()

        bar:SetScript("OnUpdate", function(self, elapsed)
            local progress = (GetTime() - fadeStartTime) / fadeDuration
            if progress >= 1 then
                self:SetAlpha(1)
                self:Hide()
                self:SetScript("OnUpdate", nil)
                self._ddingFading = nil
                -- Cleanup
                self.castGUID = nil
                self.castBarID = nil
                self.isChannel = nil
                self.isEmpowered = nil
                self.numStages = nil
            else
                self:SetAlpha(1 - progress)
            end
        end)
        return
    end

    -- Normal cleanup (successful cast or fade disabled)
    bar.castGUID  = nil
    bar.castBarID = nil
    bar.isChannel = nil
    bar.isEmpowered = nil
    bar.numStages = nil
    bar.lastNumStages = nil
    bar.currentEmpoweredStage = nil
    if bar.empoweredStages then
        for _, stage in ipairs(bar.empoweredStages) do
            if stage then
                stage:Hide()
                if stage.border then stage.border:Hide() end
            end
        end
    end
    if bar.empoweredSegments then
        for _, segment in ipairs(bar.empoweredSegments) do
            if segment then segment:Hide() end
        end
    end
    if bar.empoweredGlow then
        bar.empoweredGlow:Hide()
    end
    bar:Hide()
    bar:SetScript("OnUpdate", nil)
end

function CastBars:OnPlayerSpellcastChannelStart(unit, castGUID, spellID)
    local cfg = DDingUI.db.profile.castBar
    if not cfg.enabled then
        if DDingUI.castBar then DDingUI.castBar:Hide() end
        return
    end

    -- UnitChannelInfo now returns: name, text, texture, startTimeMS, endTimeMS, isTradeSkill, castID, notInterruptible, spellId, numStages, isEmpowered, castBarID
    -- Check UnitChannelInfo for empowered casts - if EmpowerStages (numStages) is present, it's empowered
    local name, _, texture, startTimeMS, endTimeMS, isTradeSkill, castID, notInterruptible, unitSpellID, numStages, isEmpowered, castBarID = UnitChannelInfo("player")
    if not name or not startTimeMS or not endTimeMS then
        if DDingUI.castBar then DDingUI.castBar:Hide() end
        return
    end

    local bar = self:GetCastBar()

    -- IMPORTANT: Reset alpha and cancel fade FIRST before anything else
    if bar._ddingFading then
        bar:SetScript("OnUpdate", nil)
        bar._ddingFading = nil
    end
    bar:SetAlpha(1)

    self:UpdateCastBarLayout()

    bar.isChannel = true
    bar.castGUID  = castGUID
    bar.castBarID = castBarID  -- Store castBarID for cast tracking

    -- Check if this is an empowered channel - if numStages (EmpowerStages) is present, it's empowered
    -- Following FeelUI's approach: check for EmpowerStages from UnitChannelInfo
    local isEmpoweredCast = (numStages and numStages > 0) or false
    
    bar.isEmpowered = isEmpoweredCast
    bar.numStages = numStages or 0

    bar.icon:SetTexture(texture)
    bar.spellName:SetText(name)

    local font = DDingUI:GetFont(cfg.textFont)
    bar.spellName:SetFont(font, cfg.textSize or 10, "OUTLINE")
    bar.spellName:SetShadowOffset(0, 0)

    bar.timeText:SetFont(font, cfg.textSize or 10, "OUTLINE")
    bar.timeText:SetShadowOffset(0, 0)

    bar.startTime = startTimeMS / 1000
    bar.endTime   = endTimeMS / 1000

    -- Initialize empowered stages only if this is actually an empowered channel
    if bar.isEmpowered and bar.numStages > 0 then
        -- Delay initialization slightly to ensure bar is properly sized
        C_Timer.After(0.01, function()
            if bar.isEmpowered and bar.numStages > 0 then
                if CastBars.InitializeEmpoweredStages then
                    CastBars:InitializeEmpoweredStages(bar)
                end
            end
        end)
    else
        -- Clean up any existing empowered stages if this is a regular channel
        if bar.empoweredStages then
            for _, stage in ipairs(bar.empoweredStages) do
                if stage then
                    stage:Hide()
                    if stage.border then
                        stage.border:Hide()
                    end
                end
            end
        end
        if bar.empoweredSegments then
            for _, segment in ipairs(bar.empoweredSegments) do
                if segment then
                    segment:Hide()
                end
            end
        end
        if bar.empoweredGlow then
            bar.empoweredGlow:Hide()
        end
    end

    bar:SetScript("OnUpdate", CastBar_OnUpdate)
    bar:Show()
end

function CastBars:OnPlayerSpellcastChannelUpdate(unit, castGUID, spellID)
    if not DDingUI.castBar then return end
    if DDingUI.castBar.castGUID and castGUID and castGUID ~= DDingUI.castBar.castGUID then
        return
    end

    local name, _, texture, startTimeMS, endTimeMS, isTradeSkill, castID, notInterruptible, unitSpellID, numStages, isEmpowered, castBarID = UnitChannelInfo("player")
    if not name or not startTimeMS or not endTimeMS then
        return
    end

    local bar = DDingUI.castBar
    bar.isChannel = true
    bar.castGUID  = castGUID
    bar.castBarID = castBarID  -- Update castBarID
    
    -- Update empowered status - check for EmpowerStages (numStages) from UnitChannelInfo
    local isEmpoweredCast = (numStages and numStages > 0) or false
    bar.isEmpowered = isEmpoweredCast
    bar.numStages = numStages or 0

    bar.icon:SetTexture(texture)
    bar.spellName:SetText(name)

    bar.startTime = startTimeMS / 1000
    bar.endTime   = endTimeMS / 1000
    
    -- Reinitialize empowered stages if needed
    if bar.isEmpowered and bar.numStages > 0 then
        if bar.numStages ~= (bar.lastNumStages or 0) then
            bar.lastNumStages = bar.numStages
            if CastBars.InitializeEmpoweredStages then
                CastBars:InitializeEmpoweredStages(bar)
            end
        end
    end
end

-- Expose to main addon for backwards compatibility
DDingUI.GetCastBar = function(self) return CastBars:GetCastBar() end
DDingUI.UpdateCastBarLayout = function(self) return CastBars:UpdateCastBarLayout() end
DDingUI.OnPlayerSpellcastStart = function(self, unit, castGUID, spellID) return CastBars:OnPlayerSpellcastStart(unit, castGUID, spellID) end
DDingUI.OnPlayerSpellcastStop = function(self, unit, castGUID, spellID) return CastBars:OnPlayerSpellcastStop(unit, castGUID, spellID) end
DDingUI.OnPlayerSpellcastChannelStart = function(self, unit, castGUID, spellID) return CastBars:OnPlayerSpellcastChannelStart(unit, castGUID, spellID) end
DDingUI.OnPlayerSpellcastChannelUpdate = function(self, unit, castGUID, spellID) return CastBars:OnPlayerSpellcastChannelUpdate(unit, castGUID, spellID) end


