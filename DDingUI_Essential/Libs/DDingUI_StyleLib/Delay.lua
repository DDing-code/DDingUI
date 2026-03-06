------------------------------------------------------
-- DDingUI_StyleLib :: Delay
-- Throttle / Debounce 유틸리티 (inspired by AF)
------------------------------------------------------
local MAJOR = "DDingUI-StyleLib-1.0"
local Lib = LibStub:GetLibrary(MAJOR)
if not Lib then return end

local GetTime = GetTime

---------------------------------------------------------------------
-- Throttle (최소 간격 보장 — 첫 호출 즉시 실행)
---------------------------------------------------------------------

--- 함수를 최소 interval 간격으로만 실행하는 래퍼 반환
--- @param interval number  최소 실행 간격 (초)
--- @param func function
--- @return function throttled
function Lib.Throttle(interval, func)
    local lastCall = 0
    return function(...)
        local now = GetTime()
        if now - lastCall >= interval then
            lastCall = now
            return func(...)
        end
    end
end

---------------------------------------------------------------------
-- Debounce (마지막 호출로부터 delay 후 실행)
---------------------------------------------------------------------

--- 마지막 호출로부터 delay초 후에 실행하는 래퍼 반환
--- @param delay number  지연 시간 (초)
--- @param func function
--- @return function debounced
function Lib.Debounce(delay, func)
    local timer
    return function(...)
        local args = { ... }
        if timer then timer:Cancel() end
        timer = C_Timer.NewTimer(delay, function()
            timer = nil
            func(unpack(args))
        end)
    end
end

---------------------------------------------------------------------
-- DelayedInvoker (delay 후 1회 실행, 중복 호출 시 타이머 리셋)
---------------------------------------------------------------------

--- 지연 실행 래퍼 (이벤트 핸들러에 유용)
--- @param delay number
--- @param func function
--- @return function invoker
function Lib.DelayedInvoker(delay, func)
    local timer
    return function(...)
        if timer then timer:Cancel() end
        local args = { ... }
        timer = C_Timer.NewTimer(delay, function()
            timer = nil
            func(unpack(args))
        end)
    end
end
