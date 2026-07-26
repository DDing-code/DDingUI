local ns = select(2, ...)
local DDingUI = ns.Addon

local DurationDriver = {}
DDingUI.BuffTrackerDurationDriver = DurationDriver

function DurationDriver.Create(DURATION_UPDATE_INTERVAL, math_max)
    local function ShouldRunDurationUpdate(frame, elapsed, interval)
        local updateInterval = interval or frame._ddDurationUpdateInterval or DURATION_UPDATE_INTERVAL
        if updateInterval <= 0 then
            frame._ddDurationUpdateElapsed = nil
            return true
        end
        frame._ddDurationUpdateElapsed = (frame._ddDurationUpdateElapsed or 0) + (elapsed or 0)
        if frame._ddDurationUpdateElapsed < updateInterval then
            return false
        end
        frame._ddDurationUpdateElapsed = 0
        return true
    end

    local function ShouldRunDurationTextUpdate(frame, elapsed)
        frame._ddDurationTextElapsed = (frame._ddDurationTextElapsed or 0) + (elapsed or 0)
        if frame._ddDurationTextElapsed < DURATION_UPDATE_INTERVAL then
            return false
        end
        frame._ddDurationTextElapsed = 0
        return true
    end

    local durationDriverFrame
    local durationDriverHandlers = {}
    local durationDriverCount = 0

    local function EnsureDurationDriver()
        if durationDriverFrame then return durationDriverFrame end
        durationDriverFrame = CreateFrame("Frame")
        durationDriverFrame:Hide()
        durationDriverFrame:SetScript("OnUpdate", function(self, elapsed)
            if durationDriverCount <= 0 then
                self:Hide()
                return
            end

            for owner, handler in pairs(durationDriverHandlers) do
                if owner and handler then
                    if not owner.IsShown or owner:IsShown() then
                        handler(owner, elapsed)
                    end
                else
                    durationDriverHandlers[owner] = nil
                end
            end
        end)
        return durationDriverFrame
    end

    local function RegisterDurationUpdate(owner, handler)
        if not owner or not handler then return end
        if not durationDriverHandlers[owner] then
            durationDriverCount = durationDriverCount + 1
        end
        durationDriverHandlers[owner] = handler
        EnsureDurationDriver():Show()
    end

    local function UnregisterDurationUpdate(owner)
        if not owner then return end
        if durationDriverHandlers[owner] then
            durationDriverHandlers[owner] = nil
            durationDriverCount = math_max(0, durationDriverCount - 1)
        end
        owner._ddDurationUpdateElapsed = nil
        owner._ddDurationTextElapsed = nil
        owner._dtElapsed = nil
        owner._textElapsed = nil
        if durationDriverFrame and durationDriverCount <= 0 then
            durationDriverFrame:Hide()
        end
    end


    return ShouldRunDurationUpdate, ShouldRunDurationTextUpdate,
        RegisterDurationUpdate, UnregisterDurationUpdate
end
