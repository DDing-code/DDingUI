"""Regression check for totem state and suppressed CustomIcons source frames."""
from pathlib import Path

from lupa.lua51 import LuaRuntime


ROOT = Path(__file__).parent
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
function CreateFrame()
    return {SetScript=function() end, RegisterEvent=function() end,
        UnregisterAllEvents=function() end}
end
function wipe(t) for k in pairs(t) do t[k] = nil end end
function GetNumTotemSlots() return 5 end
durations = {}
function GetTotemDuration(slot) return durations[slot] end
function GetTotemInfo(slot) return durations[slot] ~= nil, nil, 0, 10, 300000 + slot end
addon = {}
local function cooldown()
    return {shown=false, Show=function(s) s.shown=true end,
        Hide=function(s) s.shown=false end, IsShown=function(s) return s.shown end,
        Clear=function(s) s.duration=nil end, SetReverse=function() end,
        SetDrawBling=function() end,
        SetCooldownFromDurationObject=function(s, duration) s.duration=duration end}
end
function makeTotemFrame()
    return {cooldown=cooldown(), cooldownProbe=cooldown(),
        icon={SetTexture=function(s, texture) s.texture=texture end,
            SetDesaturation=function() end},
        count={SetText=function() end, Hide=function() end}}
end
''')
ns = lua.table(Addon=lua.globals().addon)
for path in (
    "DDingUI_CDM/Modules/CustomIcons/TotemTracker.lua",
    "DDingUI_CDM/Modules/GroupSystem/DynamicIconBridge.lua",
):
    lua.execute((ROOT / path).read_text(encoding="utf-8-sig"), "DDingUI_CDM", ns)
lua.execute(r'''
local tracker = addon.CustomIconTotems
assert(tracker:GetNumSlots() == 5)
local frames = {}
for slot = 1, 5 do
    local frame = makeTotemFrame()
    frames[slot] = frame
    tracker:RegisterFrame(frame, {type="totem", totemSlot=slot})
    assert(frame._ddTotemActive == false)
end
durations[3] = {}
frames[3].cooldownProbe.Show = function() end -- visibility cannot drive state
tracker:RefreshSlot(3)
assert(frames[3]._ddTotemActive == true)
assert(frames[3].cooldown:IsShown())
assert(frames[3].icon.texture == 300003)
durations[3] = nil
tracker:RefreshSlot(3)
assert(frames[3]._ddTotemActive == false)
assert(not frames[3].cooldown:IsShown())

local source = {shown=true, Hide=function(s) s.shown=false end}
addon.CustomIcons = {GetGroupFrames=function() return {totems=source} end}
local bridge = addon.DynamicIconBridge
assert(not bridge:IsActive())
bridge:SuppressCustomIconsLayout()
assert(bridge:IsActive()) -- suppression starts before full GroupSystem initialization
assert(not source.shown) -- no second copy at the source group's default anchor
''')
print("totem ghost regression: OK")
