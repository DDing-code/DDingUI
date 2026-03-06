local ADDON_NAME, ns = ...
local DDingUI = ns.Addon

-- Get CastBars module
local CastBars = DDingUI.CastBars
if not CastBars then
    error("DDingUI: CastBars module not initialized! Load CastBars.lua first.")
end

-- EMPOWERED CAST FUNCTIONS

-- Empower stage colors matching FeelUI's scheme
local EmpowerStageColors = {
    [1] = {0.3, 0.75, 1, 1},      -- Light blue / Teal
    [2] = {0.4, 1, 0.4, 1},        -- Light green
    [3] = {1, 0.85, 0, 1},         -- Yellow / Golden
    [4] = {1, 0.5, 0, 1},          -- Orange / Reddish-brown
    [5] = {1, 0.2, 0.2, 1},        -- Red
}

-- Light/glow versions of stage colors (for glow effect)
local EmpowerStageGlowColors = {
    [1] = {0.5, 0.9, 1, 0.6},      -- Light blue glow
    [2] = {0.6, 1, 0.6, 0.6},      -- Light green glow
    [3] = {1, 0.95, 0.3, 0.6},     -- Yellow glow
    [4] = {1, 0.7, 0.3, 0.6},      -- Orange glow
    [5] = {1, 0.4, 0.4, 0.6},      -- Red glow
}

function CastBars:InitializeEmpoweredStages(bar)
    if not bar or not bar.isEmpowered or not bar.numStages or bar.numStages <= 0 then
        return
    end
    
    -- Verify the cast is still active - if startTime is missing or invalid, don't initialize
    if not bar.startTime or not bar.endTime then
        return
    end
    local now = GetTime()
    if now >= bar.endTime then
        -- Cast has already ended, don't initialize
        return
    end

    -- Clean up existing stages
    if bar.empoweredStages then
        for _, stage in ipairs(bar.empoweredStages) do
            if stage then
                stage:Hide()
                if stage.border then
                    stage.border:Hide()
                end
            end
        end
    else
        bar.empoweredStages = {}
    end
    
    -- Clean up segments (including blank period segment at index 0 and hold-to-max at index -1)
    -- Fully reset all segments to ensure clean state
    if bar.empoweredSegments then
        -- Clean up blank period segment
        if bar.empoweredSegments[0] then
            bar.empoweredSegments[0]:ClearAllPoints()
            bar.empoweredSegments[0]:Hide()
        end
        -- Clean up hold-to-max segment
        if bar.empoweredSegments[-1] then
            bar.empoweredSegments[-1]:ClearAllPoints()
            bar.empoweredSegments[-1]:Hide()
        end
        -- Clean up stage segments
        for _, segment in ipairs(bar.empoweredSegments) do
            if segment then
                segment:ClearAllPoints()
                segment:Hide()
            end
        end
    end
    
    -- Clean up segment fills - CRITICAL: Reset all fills to 0 width to prevent old state
    if bar.empoweredSegmentFills then
        -- Reset blank period fill
        if bar.empoweredSegmentFills[0] then
            bar.empoweredSegmentFills[0]:SetWidth(0)
            bar.empoweredSegmentFills[0]:ClearAllPoints()
            bar.empoweredSegmentFills[0]:Hide()
        end
        -- Reset hold-to-max fill
        if bar.empoweredSegmentFills[-1] then
            bar.empoweredSegmentFills[-1]:SetWidth(0)
            bar.empoweredSegmentFills[-1]:ClearAllPoints()
            bar.empoweredSegmentFills[-1]:Hide()
        end
        -- Reset stage fills
        for _, fill in ipairs(bar.empoweredSegmentFills) do
            if fill then
                fill:SetWidth(0)  -- CRITICAL: Reset width to 0
                fill:ClearAllPoints()
                fill:Hide()
            end
        end
    else
        bar.empoweredSegmentFills = {}
    end
    
    -- Hide glow
    if bar.empoweredGlow then
        bar.empoweredGlow:Hide()
    end

    -- Create stage markers and segments
    local status = bar.status
    if not status then return end
    
    -- Create glow overlay for stage transitions
    if not bar.empoweredGlow then
        bar.empoweredGlow = status:CreateTexture(nil, "OVERLAY")
        bar.empoweredGlow:SetAllPoints(status)
        bar.empoweredGlow:SetBlendMode("ADD")
        bar.empoweredGlow:Hide()
    end
    
    -- Initialize stage segments storage
    -- IMPORTANT: Don't clear the tables entirely - we want to reuse texture objects to avoid creating new ones
    -- But we DO need to fully reset their state
    if not bar.empoweredSegments then
        bar.empoweredSegments = {}
    end
    if not bar.empoweredSegmentFills then
        bar.empoweredSegmentFills = {}
    end
    
    -- Ensure all existing segments are fully reset (already done above, but double-check)
    -- This ensures clean state when transitioning from regular to empowered cast

    -- Wait a frame for the bar to be properly sized
    C_Timer.After(0, function()
        -- 재시도 횟수 제한 (무한 재귀 방지)
        bar._empoweredRetryCount = (bar._empoweredRetryCount or 0)

        -- Check if frame is ready by checking visibility instead of comparing width
        -- This avoids taint issues with GetWidth() comparisons
        if not status:IsVisible() then
            bar._empoweredRetryCount = bar._empoweredRetryCount + 1
            if bar._empoweredRetryCount < 10 then
                C_Timer.After(0.05, function()
                    CastBars:InitializeEmpoweredStages(bar)
                end)
            end
            return
        end

        -- Calculate width from bar dimensions to avoid taint from GetWidth()
        -- Status bar width = bar width - icon width
        local cfg = DDingUI.db.profile.castBar
        local barHeight = (cfg and cfg.height) or 24
        local iconWidth = DDingUI:Scale(barHeight)  -- Icon width equals bar height

        -- Get bar width safely - bar width is set by our code so should be less tainted
        local barOk, barW = pcall(function() return bar:GetWidth() end)
        if not barOk then
            bar._empoweredRetryCount = bar._empoweredRetryCount + 1
            if bar._empoweredRetryCount < 10 then
                C_Timer.After(0.05, function()
                    CastBars:InitializeEmpoweredStages(bar)
                end)
            end
            return
        end

        -- 성공 시 카운터 리셋
        bar._empoweredRetryCount = 0
        
        -- Calculate status bar width: bar width - icon width
        local barWidth = (tonumber(barW) or 200) - iconWidth
        if barWidth < 0 then barWidth = 100 end  -- Safety fallback
        
        -- Get stage height
        local cfg = DDingUI.db.profile.castBar
        local stageHeight = (cfg and cfg.height) or 24
        
        -- Calculate border offset to keep segments and ticks within border
        -- This is calculated once and reused for all segments and ticks
        local borderOffset = (DDingUI.ScaleBorder and DDingUI:ScaleBorder(1)) or math.floor((DDingUI:Scale(1) or 1) + 0.5)

        -- Use the new UnitEmpoweredStageDurations API to get accurate stage durations
        -- This returns duration objects for each stage, with the final element being hold-at-max
        local tickPositions = {}
        local unitToken = "player"
        local totalDuration = 0
        local stage1StartPercent = 0
        
        -- Try to use UnitEmpoweredStageDurations first (new API)
        if UnitEmpoweredStageDurations then
            local stageDurations = UnitEmpoweredStageDurations(unitToken)
            if stageDurations and #stageDurations > 0 then
                -- Calculate total duration (sum of all stages including hold-at-max)
                for i = 1, #stageDurations do
                    if stageDurations[i] and stageDurations[i].durationMS then
                        totalDuration = totalDuration + (stageDurations[i].durationMS / 1000)
                    end
                end
                
                -- The first element is the initial blank period (stage 0)
                if stageDurations[1] and stageDurations[1].durationMS then
                    local blankDuration = stageDurations[1].durationMS / 1000
                    stage1StartPercent = totalDuration > 0 and (blankDuration / totalDuration) or 0
                end
                
                -- Calculate cumulative positions for each stage (excluding hold-at-max for tick positions)
                local cumulative = stage1StartPercent
                for i = 2, math.min(#stageDurations - 1, bar.numStages + 1) do  -- Exclude blank period and hold-at-max
                    if stageDurations[i] and stageDurations[i].durationMS then
                        local stageDuration = stageDurations[i].durationMS / 1000
                        cumulative = cumulative + (totalDuration > 0 and (stageDuration / totalDuration) or 0)
                        tickPositions[i - 1] = cumulative  -- i-1 because we skip the first (blank period)
                    end
                end
            end
        end
        
        -- Fallback to UnitEmpoweredStagePercentages if UnitEmpoweredStageDurations not available
        if #tickPositions == 0 and UnitEmpoweredStagePercentages then
            local percentages = UnitEmpoweredStagePercentages(unitToken, true)  -- includeHoldAtMaxTime = true
            if percentages and #percentages > 0 then
                -- The first percentage is the initial blank period (stage 0)
                stage1StartPercent = percentages[1] or 0
                
                -- Convert cumulative percentages to positions, starting from stage 1
                local cumulative = stage1StartPercent
                for i = 1, math.min(#percentages - 2, bar.numStages) do  -- Exclude blank period and hold-at-max
                    cumulative = cumulative + (percentages[i + 1] or 0)  -- i+1 because we skip the first
                    tickPositions[i] = cumulative
                end
            end
        end
        
        -- Fallback to default positions if API didn't return valid data
        if #tickPositions == 0 then
            -- Default positions based on number of stages
            if bar.numStages == 4 then
                tickPositions = {0.21, 0.42, 0.63, 0.84}
            elseif bar.numStages == 3 then
                tickPositions = {0.20, 0.38, 0.63}
            else
                -- Generic fallback: distribute evenly
                for i = 1, bar.numStages do
                    tickPositions[i] = i / (bar.numStages + 1)
                end
            end
        end
        
        -- Create segment backgrounds and fills for each stage
        -- Initialize segments storage
        if not bar.empoweredSegments then
            bar.empoweredSegments = {}
        end
        if not bar.empoweredSegmentFills then
            bar.empoweredSegmentFills = {}
        end
        
        -- Get stage colors from config
        local cfg = DDingUI.db.profile.castBar
        local stageColors = cfg and cfg.empoweredStageColors or {}
        local defaultColors = {
            [1] = {0.3, 0.75, 1, 1},      -- Light blue / Teal
            [2] = {1, 0.75, 0.3, 1},      -- Amber/Gold
            [3] = {0.7, 0.1, 0.1, 1},     -- Dark red
            [4] = {1, 0.5, 0, 1},          -- Orange
            [5] = {1, 0.2, 0.2, 1},        -- Red
        }
        
        -- Check if stage colors should be shown
        local showStageColors = true  -- Default to true
        if cfg and cfg.showEmpoweredStageColors == false then
            showStageColors = false
        end
        
        -- Neutral color for inactive segments
        local neutralColor = {0.1, 0.1, 0.1, 1}  -- Very dark gray
        
        -- Create initial blank period segment (from 0 to stage1StartPercent)
        -- This uses the regular cast bar colors (custom color and background color)
        if stage1StartPercent > 0 then
            local blankSegmentBg = bar.empoweredSegments[0]
            if not blankSegmentBg then
                blankSegmentBg = status:CreateTexture(nil, "BACKGROUND", nil, -3)
                bar.empoweredSegments[0] = blankSegmentBg
            end
            
            local blankSegmentWidth = stage1StartPercent * barWidth
            -- Calculate border offset
            local borderOffset = (DDingUI.ScaleBorder and DDingUI:ScaleBorder(1)) or math.floor((DDingUI:Scale(1) or 1) + 0.5)
            
            blankSegmentBg:ClearAllPoints()
            blankSegmentBg:SetPoint("LEFT", status, "LEFT", 0, 0)
            blankSegmentBg:SetPoint("TOP", status, "TOP", 0, -borderOffset)  -- Inset from top to stay within border
            blankSegmentBg:SetPoint("BOTTOM", status, "BOTTOM", 0, borderOffset)  -- Inset from bottom to stay within border
            blankSegmentBg:SetWidth(blankSegmentWidth)
            
            -- Use regular cast bar background color
            local bgColor = cfg and cfg.bgColor or { 0.1, 0.1, 0.1, 1 }
            blankSegmentBg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)
            blankSegmentBg:Show()
            
            -- Create blank period fill (foreground)
            local blankSegmentFill = bar.empoweredSegmentFills[0]
            if not blankSegmentFill then
                blankSegmentFill = status:CreateTexture(nil, "ARTWORK", nil, 1)
                bar.empoweredSegmentFills[0] = blankSegmentFill
                -- Use the same texture as the status bar
                local statusTex = status:GetStatusBarTexture()
                if statusTex then
                    local texPath = statusTex:GetTexture()
                    if texPath then
                        blankSegmentFill:SetTexture(texPath)
                    else
                        -- Fallback to solid color texture
                        blankSegmentFill:SetColorTexture(1, 1, 1, 1)
                    end
                else
                    -- Fallback to solid color texture
                    blankSegmentFill:SetColorTexture(1, 1, 1, 1)
                end
            end
            
            blankSegmentFill:ClearAllPoints()
            blankSegmentFill:SetPoint("LEFT", status, "LEFT", 0, 0)
            blankSegmentFill:SetPoint("TOP", status, "TOP", 0, -borderOffset)  -- Inset from top to stay within border
            blankSegmentFill:SetPoint("BOTTOM", status, "BOTTOM", 0, borderOffset)  -- Inset from bottom to stay within border
            blankSegmentFill:SetWidth(0)  -- Will be set in OnUpdate based on progress
            blankSegmentFill:Hide()
        end
        
        -- Calculate where the hold-to-max period starts (end of last actual stage)
        -- The hold-to-max period is the final 1 second, so we need to find where the last stage ends
        -- We'll calculate this by summing all stage percentages (excluding blank period and hold-to-max)
        local lastStageEndPercent = stage1StartPercent
        if #tickPositions > 0 and bar.numStages > 0 then
            -- If we have tick positions, the last stage starts at the last tick position
            -- We need to add the last stage's duration to get where it ends
            -- For now, estimate the last stage size as the average stage size
            if bar.numStages > 1 then
                local lastTickPos = tickPositions[bar.numStages - 1] or stage1StartPercent
                -- Estimate last stage size (average of other stages)
                local avgStageSize = (lastTickPos - stage1StartPercent) / (bar.numStages - 1)
                lastStageEndPercent = lastTickPos + avgStageSize
            else
                -- Only one stage - it takes up the remaining space before hold-to-max
                -- Estimate hold-to-max as ~10% of total, so last stage ends at ~90%
                lastStageEndPercent = 0.9
            end
        else
            -- Fallback: calculate based on number of stages
            -- Estimate hold-to-max as ~10% of total duration
            local stageArea = 0.9 - stage1StartPercent  -- 90% for stages, 10% for hold-to-max
            local stageSize = stageArea / bar.numStages
            lastStageEndPercent = stage1StartPercent + (bar.numStages * stageSize)
        end
        
        -- Ensure hold-to-max starts before 1.0
        local holdAtMaxStartPercent = math.min(math.max(lastStageEndPercent, stage1StartPercent), 0.95)
        local holdAtMaxEndPercent = 1.0
        
        -- Create segment backgrounds and fills for each stage
        -- Start from stage1StartPercent (after the initial blank period)
        local prevPosition = stage1StartPercent
        for i = 1, bar.numStages do
            -- Calculate segment position and width
            -- For the final stage, end at holdAtMaxStartPercent (before hold-to-max period)
            local segmentEnd
            if i == bar.numStages then
                segmentEnd = holdAtMaxStartPercent
            else
                segmentEnd = tickPositions[i] or (prevPosition + (1.0 - stage1StartPercent) / bar.numStages)
            end
            local segmentStart = prevPosition
            local segmentWidth = (segmentEnd - segmentStart) * barWidth
            
            -- Create segment background (the colored background for this stage)
            local segmentBg = bar.empoweredSegments[i]
            if not segmentBg then
                segmentBg = status:CreateTexture(nil, "BACKGROUND", nil, -3)
                bar.empoweredSegments[i] = segmentBg
            end
            
            segmentBg:ClearAllPoints()
            segmentBg:SetPoint("LEFT", status, "LEFT", segmentStart * barWidth, 0)
            segmentBg:SetPoint("TOP", status, "TOP", 0, -borderOffset)  -- Inset from top to stay within border
            segmentBg:SetPoint("BOTTOM", status, "BOTTOM", 0, borderOffset)  -- Inset from bottom to stay within border
            segmentBg:SetWidth(segmentWidth)
            
            if showStageColors then
                -- Set to this stage's color at 50% darkness (all segments are always colored)
                local color = stageColors[i] or defaultColors[i] or defaultColors[1]
                local stageAlpha = color[4] or 1  -- Get alpha from color, use same for background and foreground
                segmentBg:SetColorTexture(color[1] * 0.5, color[2] * 0.5, color[3] * 0.5, stageAlpha)
                segmentBg:Show()
            else
                -- Hide segment background if stage colors are disabled
                segmentBg:Hide()
            end
            
            -- Create segment fill (the progress fill for this stage)
            local segmentFill = bar.empoweredSegmentFills[i]
            if not segmentFill then
                segmentFill = status:CreateTexture(nil, "ARTWORK", nil, 1)
                bar.empoweredSegmentFills[i] = segmentFill
                -- Use the same texture as the status bar
                local statusTex = status:GetStatusBarTexture()
                if statusTex then
                    local texPath = statusTex:GetTexture()
                    if texPath then
                        segmentFill:SetTexture(texPath)
                    else
                        -- Fallback to solid color texture
                        segmentFill:SetColorTexture(1, 1, 1, 1)
                    end
                else
                    -- Fallback to solid color texture
                    segmentFill:SetColorTexture(1, 1, 1, 1)
                end
            end
            
            segmentFill:ClearAllPoints()
            segmentFill:SetPoint("LEFT", status, "LEFT", segmentStart * barWidth, 0)
            segmentFill:SetPoint("TOP", status, "TOP", 0, -borderOffset)  -- Inset from top to stay within border
            segmentFill:SetPoint("BOTTOM", status, "BOTTOM", 0, borderOffset)  -- Inset from bottom to stay within border
            segmentFill:SetWidth(0)  -- Will be set in OnUpdate based on progress
            -- Initially hide - will be shown and colored in OnUpdate based on current stage
            segmentFill:Hide()
            
            prevPosition = segmentEnd
        end
        
        -- Create hold-to-max segment (the final 1 second period)
        -- This uses the final stage's color
        if holdAtMaxStartPercent < 1.0 then
            local holdAtMaxSegmentBg = bar.empoweredSegments[-1]  -- Use -1 as index for hold-to-max
            if not holdAtMaxSegmentBg then
                holdAtMaxSegmentBg = status:CreateTexture(nil, "BACKGROUND", nil, -3)
                bar.empoweredSegments[-1] = holdAtMaxSegmentBg
            end
            
            local holdAtMaxSegmentWidth = (holdAtMaxEndPercent - holdAtMaxStartPercent) * barWidth
            holdAtMaxSegmentBg:ClearAllPoints()
            holdAtMaxSegmentBg:SetPoint("LEFT", status, "LEFT", holdAtMaxStartPercent * barWidth, 0)
            holdAtMaxSegmentBg:SetPoint("TOP", status, "TOP", 0, -borderOffset)  -- Inset from top to stay within border
            holdAtMaxSegmentBg:SetPoint("BOTTOM", status, "BOTTOM", 0, borderOffset)  -- Inset from bottom to stay within border
            holdAtMaxSegmentBg:SetWidth(holdAtMaxSegmentWidth)
            
            if showStageColors then
                -- Use final stage's color at 50% darkness for background
                local finalStageColor = stageColors[bar.numStages] or defaultColors[bar.numStages] or defaultColors[1]
                local finalStageAlpha = finalStageColor[4] or 1
                holdAtMaxSegmentBg:SetColorTexture(finalStageColor[1] * 0.5, finalStageColor[2] * 0.5, finalStageColor[3] * 0.5, finalStageAlpha)
                holdAtMaxSegmentBg:Show()
            else
                holdAtMaxSegmentBg:Hide()
            end
            
            -- Create hold-to-max fill (foreground)
            local holdAtMaxSegmentFill = bar.empoweredSegmentFills[-1]
            if not holdAtMaxSegmentFill then
                holdAtMaxSegmentFill = status:CreateTexture(nil, "ARTWORK", nil, 1)
                bar.empoweredSegmentFills[-1] = holdAtMaxSegmentFill
                -- Use the same texture as the status bar
                local statusTex = status:GetStatusBarTexture()
                if statusTex then
                    local texPath = statusTex:GetTexture()
                    if texPath then
                        holdAtMaxSegmentFill:SetTexture(texPath)
                    else
                        -- Fallback to solid color texture
                        holdAtMaxSegmentFill:SetColorTexture(1, 1, 1, 1)
                    end
                else
                    -- Fallback to solid color texture
                    holdAtMaxSegmentFill:SetColorTexture(1, 1, 1, 1)
                end
            end
            
            holdAtMaxSegmentFill:ClearAllPoints()
            holdAtMaxSegmentFill:SetPoint("LEFT", status, "LEFT", holdAtMaxStartPercent * barWidth, 0)
            holdAtMaxSegmentFill:SetPoint("TOP", status, "TOP", 0, -borderOffset)  -- Inset from top to stay within border
            holdAtMaxSegmentFill:SetPoint("BOTTOM", status, "BOTTOM", 0, borderOffset)  -- Inset from bottom to stay within border
            holdAtMaxSegmentFill:SetWidth(0)  -- Will be set in OnUpdate based on progress
            holdAtMaxSegmentFill:Hide()
        end
        
        -- Check if we should show empowered ticks
        local cfg = DDingUI.db.profile.castBar
        -- Default to true if not set, but respect false when explicitly set
        -- Only hide ticks if showEmpoweredTicks is explicitly set to false
        local showTicks = true  -- Default to true
        if cfg and cfg.showEmpoweredTicks == false then
            showTicks = false
        end
        
        if showTicks then
            -- Calculate segment start positions for tick placement
            -- Ticks should be at the FRONT (beginning) of each segment, not the back
            local segmentStartPositions = {}
            local prevPos = stage1StartPercent
            for i = 1, bar.numStages do
                segmentStartPositions[i] = prevPos
                -- Move to next segment start (which is the end of current segment)
                if i < bar.numStages then
                    prevPos = tickPositions[i] or (prevPos + (1.0 - stage1StartPercent) / bar.numStages)
                end
            end
            
            for i = 1, bar.numStages do
                local stage = bar.empoweredStages[i]
                if not stage then
                    -- Create the main stage tick texture
                    stage = status:CreateTexture(nil, "OVERLAY")
                    stage:SetWidth(2)
                    
                    -- Create border texture for the tick
                    local border = status:CreateTexture(nil, "BORDER")
                    border:SetColorTexture(0, 0, 0, 1)  -- Black border
                    border:SetWidth(4)  -- 2px tick + 1px border on each side
                    stage.border = border
                    
                    bar.empoweredStages[i] = stage
                end

                -- Get height from config to avoid taint issues with GetHeight()
                -- Use config value instead of reading from frame
                local stageHeight = (cfg and cfg.height) or 24  -- Default to 24 if config not available
                -- Inset tick height to stay within border
                local tickHeight = stageHeight - (borderOffset * 2)
                stage:SetHeight(math.max(1, tickHeight))  -- Ensure at least 1 pixel height
                
                -- Set border height (tick height + 2px for top and bottom borders, but inset to stay within border)
                if stage.border then
                    stage.border:SetHeight(math.max(3, tickHeight + 2))  -- Ensure at least 3 pixels for border
                end

                -- Color each stage tick using the user's configured stage color
                local stageColors = cfg and cfg.empoweredStageColors or {}
                local defaultColors = {
                    [1] = {0.3, 0.75, 1, 1},      -- Light blue / Teal
                    [2] = {1, 0.75, 0.3, 1},      -- Amber/Gold
                    [3] = {0.7, 0.1, 0.1, 1},     -- Dark red
                    [4] = {1, 0.5, 0, 1},          -- Orange
                    [5] = {1, 0.2, 0.2, 1},        -- Red
                }
                local tickColor = stageColors[i] or defaultColors[i] or defaultColors[1] or {1, 1, 1, 0.8}
                stage:SetColorTexture(tickColor[1], tickColor[2], tickColor[3], tickColor[4] or 0.8)

                -- Position stage marker at the FRONT (beginning) of the segment
                local segmentStart = segmentStartPositions[i] or stage1StartPercent
                local position = segmentStart * barWidth
                stage:ClearAllPoints()
                stage:SetPoint("LEFT", status, "LEFT", position - 1, 0)
                stage:SetPoint("TOP", status, "TOP", 0, -borderOffset)  -- Inset from top to stay within border
                stage:SetPoint("BOTTOM", status, "BOTTOM", 0, borderOffset)  -- Inset from bottom to stay within border
                
                -- Position border behind the tick (centered, slightly larger)
                if stage.border then
                    stage.border:ClearAllPoints()
                    stage.border:SetPoint("CENTER", stage, "CENTER", 0, 0)
                    stage.border:Show()
                end
                
                stage:Show()
            end
        else
            -- Hide all ticks if the setting is disabled
            if bar.empoweredStages then
                for i = 1, #bar.empoweredStages do
                    local stage = bar.empoweredStages[i]
                    if stage then
                        stage:Hide()
                        if stage.border then
                            stage.border:Hide()
                        end
                    end
                end
            end
        end
    end)
end

function CastBars:OnPlayerSpellcastEmpowerStart(unit, castGUID, spellID)
    local cfg = DDingUI.db.profile.castBar
    if not cfg or not cfg.enabled then
        return
    end

    local bar = self:GetCastBar()
    self:UpdateCastBarLayout()

    -- COMPLETE cleanup of any previous cast state to prevent issues when transitioning from regular to empowered cast
    -- This ensures segments are fully reset, not just hidden
    
    -- Reset all segment fills to 0 width and hide them
    if bar.empoweredSegmentFills then
        -- Reset blank period fill
        if bar.empoweredSegmentFills[0] then
            bar.empoweredSegmentFills[0]:SetWidth(0)
            bar.empoweredSegmentFills[0]:ClearAllPoints()
            bar.empoweredSegmentFills[0]:Hide()
        end
        -- Reset hold-to-max fill
        if bar.empoweredSegmentFills[-1] then
            bar.empoweredSegmentFills[-1]:SetWidth(0)
            bar.empoweredSegmentFills[-1]:ClearAllPoints()
            bar.empoweredSegmentFills[-1]:Hide()
        end
        -- Reset stage fills
        for _, fill in ipairs(bar.empoweredSegmentFills) do
            if fill then
                fill:SetWidth(0)
                fill:ClearAllPoints()
                fill:Hide()
            end
        end
    end
    
    -- Hide all empowered segments (backgrounds)
    if bar.empoweredSegments then
        -- Hide blank period segment
        if bar.empoweredSegments[0] then
            bar.empoweredSegments[0]:ClearAllPoints()
            bar.empoweredSegments[0]:Hide()
        end
        -- Hide hold-to-max segment
        if bar.empoweredSegments[-1] then
            bar.empoweredSegments[-1]:ClearAllPoints()
            bar.empoweredSegments[-1]:Hide()
        end
        -- Hide stage segments
        for _, segment in ipairs(bar.empoweredSegments) do
            if segment then
                segment:ClearAllPoints()
                segment:Hide()
            end
        end
    end
    
    -- Hide empowered ticks
    if bar.empoweredStages then
        for _, stage in ipairs(bar.empoweredStages) do
            if stage then
                stage:ClearAllPoints()
                stage:Hide()
                if stage.border then
                    stage.border:ClearAllPoints()
                    stage.border:Hide()
                end
            end
        end
    end
    
    -- Reset empowered state completely
    bar.isEmpowered = false
    bar.numStages = 0
    bar.lastNumStages = nil
    bar.currentEmpoweredStage = nil

    -- Use UnitCastingInfo for empowered casts (like PlayersCastbars does)
    -- UnitCastingInfo returns: name, text, texture, startTimeMS, endTimeMS, isTradeSkill, castID, notInterruptible, spellId, numStages, isEmpowered, castBarID
    local name, _, texture, startTimeMS, endTimeMS, isTradeSkill, castID, notInterruptible, unitSpellID, numStages, isEmpowered, castBarID = UnitCastingInfo("player")
    
    -- If UnitCastingInfo doesn't have the data, try UnitChannelInfo as fallback
    if not name or not startTimeMS or not endTimeMS then
        name, _, texture, startTimeMS, endTimeMS, isTradeSkill, castID, notInterruptible, unitSpellID, numStages, isEmpowered, castBarID = UnitChannelInfo("player")
    end
    
    -- If still no data, try to get spell info from spellID
    if not name or not startTimeMS or not endTimeMS then
        -- Try C_Spell API if spellID is available
        if spellID and C_Spell and C_Spell.GetSpellInfo then
            local spellInfo = C_Spell.GetSpellInfo(spellID)
            if spellInfo then
                if not name then
                    name = spellInfo.name
                end
                if not texture then
                    texture = spellInfo.iconID or 136243
                end
            end
        end
        
        -- If we still don't have essential data, use defaults
        if not name then
            name = "Empowered Cast"
        end
        if not texture then
            texture = 136243
        end
        if not startTimeMS or not endTimeMS then
            -- Use UnitEmpoweredChannelDuration if available for accurate duration
            local durationObj
            if UnitEmpoweredChannelDuration then
                durationObj = UnitEmpoweredChannelDuration("player", true)  -- includeHoldAtMaxTime = true
            end
            local now = GetTime()
            if durationObj and durationObj.totalTimeMS then
                startTimeMS = now * 1000
                endTimeMS = startTimeMS + durationObj.totalTimeMS
            else
                startTimeMS = now * 1000
                -- Default to 3 second empower duration
                endTimeMS = (now + 3) * 1000
            end
        end
    end

    -- Empowered casts are NOT channels (like PlayersCastbars does)
    bar.isEmpowered = true
    bar.numStages = numStages or 3  -- Default to 3 stages if not detected
    bar.castGUID = castGUID
    bar.castBarID = castBarID  -- Store castBarID for cast tracking
    bar.isChannel = false  -- Empowered casts are NOT channels (use UnitCastingInfo, not UnitChannelInfo)

    bar.icon:SetTexture(texture)
    bar.spellName:SetText(name)

    local font = DDingUI:GetGlobalFont()
    bar.spellName:SetFont(font, cfg.textSize or 10, "OUTLINE")
    bar.spellName:SetShadowOffset(0, 0)

    bar.timeText:SetFont(font, cfg.textSize or 10, "OUTLINE")
    bar.timeText:SetShadowOffset(0, 0)

    local now = GetTime()
    
    -- Always use the API's startTimeMS - this is the actual start time of the empowered cast
    -- Don't use any previous startTime that might be lingering from a regular cast
    bar.startTime = startTimeMS / 1000
    bar.endTime = endTimeMS / 1000
    
    -- Add 1 second for hold-at-max period (empowered casts can be held for 1 more second)
    bar.endTime = bar.endTime + 1.0

    -- Safety: if start time is very old (more than 5 seconds ago), clamp to now
    -- This handles cases where the API returns stale data
    if bar.startTime < now - 5 then
        local dur = (endTimeMS - startTimeMS) / 1000
        bar.startTime = now
        bar.endTime = now + dur + 1.0  -- Add 1 second for hold-at-max
    end
    
    -- Ensure we're not using stale progress from a previous cast
    -- Reset any progress-related state
    bar.currentEmpoweredStage = nil

    -- Initialize empowered stages
    if bar.numStages and bar.numStages > 0 then
        -- Delay slightly to ensure bar is sized and state is clean
        C_Timer.After(0.01, function()
            if bar.isEmpowered and bar.numStages > 0 and bar.isEmpowered then
                -- Double-check we're still in an empowered cast before initializing
                self:InitializeEmpoweredStages(bar)
            end
        end)
    end

    bar:SetScript("OnUpdate", CastBars.CastBar_OnUpdate)
    bar:Show()
end

function CastBars:OnPlayerSpellcastEmpowerUpdate(unit, castGUID, spellID)
    if not DDingUI.castBar then return end
    if DDingUI.castBar.castGUID and castGUID and castGUID ~= DDingUI.castBar.castGUID then
        return
    end

    local bar = DDingUI.castBar
    
    -- Update empowered cast info - use UnitCastingInfo (like PlayersCastbars does)
    local name, _, texture, startTimeMS, endTimeMS, isTradeSkill, castID, notInterruptible, unitSpellID, numStages, isEmpowered, castBarID = UnitCastingInfo("player")
    
    if startTimeMS and endTimeMS then
        local newStartTime = startTimeMS / 1000
        local newEndTime = endTimeMS / 1000
        
        -- Validate: if the new startTime is significantly different from current, use it
        -- This handles transitions from regular casts to empowered casts
        local now = GetTime()
        if not bar.startTime or math.abs(newStartTime - (bar.startTime or 0)) > 0.1 then
            -- Start time changed significantly, this is a new cast
            bar.startTime = newStartTime
            bar.endTime = newEndTime + 1.0  -- Add 1 second for hold-at-max
        else
            -- Just update endTime in case duration changed
            bar.endTime = newEndTime + 1.0
        end
        
        -- Safety: if start time is very old, clamp to now
        if bar.startTime < now - 5 then
            local dur = (endTimeMS - startTimeMS) / 1000
            bar.startTime = now
            bar.endTime = now + dur + 1.0
        end
    end
    
    -- Update castBarID
    if castBarID then
        bar.castBarID = castBarID
    end

    -- Update stages if number changed
    if numStages and numStages ~= bar.numStages then
        bar.numStages = numStages
        bar.lastNumStages = numStages
        self:InitializeEmpoweredStages(bar)
    end
end

function CastBars:OnPlayerSpellcastEmpowerStop(unit, castGUID, spellID)
    if not DDingUI.castBar then return end

    if castGUID and DDingUI.castBar.castGUID and castGUID ~= DDingUI.castBar.castGUID then
        return
    end

    -- Check if still casting (empowered cast may transition to regular cast)
    local name, _, texture, startTimeMS, endTimeMS, isTradeSkill, castID, notInterruptible, unitSpellID, numStages, isEmpowered, castBarID = UnitCastingInfo("player")
    if name and startTimeMS and endTimeMS then
        -- Still casting, update the bar
        DDingUI.castBar.icon:SetTexture(texture)
        DDingUI.castBar.spellName:SetText(name)
        DDingUI.castBar.startTime = startTimeMS / 1000
        DDingUI.castBar.endTime = endTimeMS / 1000
        DDingUI.castBar.castBarID = castBarID
        DDingUI.castBar.isEmpowered = false
        DDingUI.castBar.numStages = 0
        DDingUI.castBar.lastNumStages = nil
        DDingUI.castBar.currentEmpoweredStage = nil
        if DDingUI.castBar.empoweredStages then
            for _, stage in ipairs(DDingUI.castBar.empoweredStages) do
                if stage then
                    stage:Hide()
                    if stage.border then
                        stage.border:Hide()
                    end
                end
            end
        end
        if DDingUI.castBar.empoweredSegments then
            for _, segment in ipairs(DDingUI.castBar.empoweredSegments) do
                if segment then
                    segment:Hide()
                end
            end
        end
        if DDingUI.castBar.empoweredGlow then
            DDingUI.castBar.empoweredGlow:Hide()
        end
        return
    end

    -- Cast finished, hide the bar
    DDingUI.castBar.castGUID = nil
    DDingUI.castBar.castBarID = nil
    DDingUI.castBar.isChannel = nil
    DDingUI.castBar.isEmpowered = nil
    DDingUI.castBar.numStages = nil
    DDingUI.castBar.lastNumStages = nil
    DDingUI.castBar.currentEmpoweredStage = nil
    if DDingUI.castBar.empoweredStages then
        for _, stage in ipairs(DDingUI.castBar.empoweredStages) do
            if stage then
                stage:Hide()
                if stage.border then
                    stage.border:Hide()
                end
            end
        end
    end
    if DDingUI.castBar.empoweredSegments then
        for _, segment in ipairs(DDingUI.castBar.empoweredSegments) do
            if segment then
                segment:Hide()
            end
        end
    end
    if DDingUI.castBar.empoweredGlow then
        DDingUI.castBar.empoweredGlow:Hide()
    end
    DDingUI.castBar:Hide()
    DDingUI.castBar:SetScript("OnUpdate", nil)
end

-- Expose to main addon for backwards compatibility
DDingUI.InitializeEmpoweredStages = function(self, bar) return CastBars:InitializeEmpoweredStages(bar) end
DDingUI.OnPlayerSpellcastEmpowerStart = function(self, unit, castGUID, spellID) return CastBars:OnPlayerSpellcastEmpowerStart(unit, castGUID, spellID) end
DDingUI.OnPlayerSpellcastEmpowerUpdate = function(self, unit, castGUID, spellID) return CastBars:OnPlayerSpellcastEmpowerUpdate(unit, castGUID, spellID) end
DDingUI.OnPlayerSpellcastEmpowerStop = function(self, unit, castGUID, spellID) return CastBars:OnPlayerSpellcastEmpowerStop(unit, castGUID, spellID) end

