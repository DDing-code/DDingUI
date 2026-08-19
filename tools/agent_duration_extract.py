from pathlib import Path
import re

path = Path('DDingUI/Modules/ResourceBars/BuffTrackerBar.lua')
text = path.read_text(encoding='utf-8')


def replace_once(old, new, label):
    global text
    count = text.count(old)
    assert count == 1, f'{label}: expected 1, got {count}'
    text = text.replace(old, new, 1)


def replace_slice(start_marker, end_marker, replacement, label):
    global text
    start_count = text.count(start_marker)
    assert start_count == 1, f'{label} start: expected 1, got {start_count}'
    start = text.index(start_marker)
    end = text.index(end_marker, start)
    text = text[:start] + replacement + text[end:]


replace_once(
    'local ResolveTrackedFrame = LegacyAuraDriver.ResolveFrame\n\n-- Helper: Get spellID from cooldownID using C_CooldownViewer API (CDM API)\n',
    '''local ResolveTrackedFrame = LegacyAuraDriver.ResolveFrame

local LegacyDurationDriver = DDingUI.TrackedAuraLegacyDurationDriver
if not LegacyDurationDriver then
    error("DDingUI: TrackedAuraLegacyDurationDriver must load before BuffTrackerBar.lua")
end

-- Helper: Get spellID from cooldownID using C_CooldownViewer API (CDM API)
''',
    'duration driver binding'
)

bar_dynamic_start = '''    -- ============================================================
    -- DYNAMIC DURATION: CDM에서 실시간으로 duration 읽기
    -- ============================================================
'''
replace_slice(
    bar_dynamic_start,
    '    local current, max\n',
    '''    -- ============================================================
    -- DYNAMIC DURATION: compatibility fallback only
    -- ============================================================
    if dynamicDuration then
        stackDuration = LegacyDurationDriver.ResolveDynamicDuration(
            frame, unit, auraInstanceID, settings, stackDuration,
            hasData, isManualMode, true
        )
    end

''',
    'bar dynamic duration'
)

ring_timing_start = '    -- Duration 데이터 가져오기\n'
ring_timing_end = '''    -- ============================================================
    -- DYNAMIC DURATION: CDM에서 실시간으로 duration 읽기 (바와 동일)
'''
replace_slice(
    ring_timing_start,
    ring_timing_end,
    '''    -- Duration 데이터 가져오기 -- compatibility fallback only
    if hasData and HasAuraInstanceID(auraInstanceID) then
        local legacyDuration, _, legacyRemaining = LegacyDurationDriver.ReadTiming(unit, auraInstanceID)
        if legacyDuration then actualDuration = legacyDuration end
        if legacyRemaining then remainingDuration = legacyRemaining end
    end

''',
    'ring timing'
)

ring_dynamic_start = '''    -- ============================================================
    -- DYNAMIC DURATION: CDM에서 실시간으로 duration 읽기 (바와 동일)
    -- ============================================================
'''
replace_slice(
    ring_dynamic_start,
    '    -- Visibility check (include preview/mover mode - uses file-local isInPreviewMode, isInMoverMode)\n',
    '''    -- ============================================================
    -- DYNAMIC DURATION: compatibility fallback only
    -- ============================================================
    if dynamicDuration then
        stackDuration = LegacyDurationDriver.ResolveDynamicDuration(
            frame, unit, auraInstanceID, settings, stackDuration,
            hasData, isManualMode, false
        )
    end

''',
    'ring dynamic duration'
)

replace_slice(
    '            -- Circular/Square/Donut/Ring 스타일: Cooldown 프레임 초기화\n',
    '            bar.StatusBar:SetMinMaxValues(0, max)\n',
    '''            -- Circular/Square/Donut/Ring legacy cooldown initialization
            if barStyle == "circular" or barStyle == "square" or barStyle == "donut" or barStyle == "ring" then
                LegacyDurationDriver.SyncAuraCooldown(
                    bar.Cooldown, bar, "_lastCooldownAuraID", unit, auraInstanceID
                )
            end

''',
    'bar duration cooldown init'
)

replace_slice(
    '            -- Circular/Square/Donut/Ring 스타일: Cooldown 프레임 초기화 (스택 모드에서도)\n',
    '            if not bar._hasDurationUpdate then\n',
    '''            -- Circular/Square/Donut/Ring legacy cooldown initialization
            if barStyle == "circular" or barStyle == "square" or barStyle == "donut" or barStyle == "ring" then
                LegacyDurationDriver.SyncAuraCooldown(
                    bar.Cooldown, bar, "_lastCooldownAuraID", unit, auraInstanceID
                )
            end

''',
    'bar stacks cooldown init'
)

replace_once(
    '''                    local resolver = DDingUI.TrackedAuraFrameResolver
                    if data.sourceFrame and resolver and resolver.MirrorProgress then
                        local progressCopied, textCopied = resolver:MirrorProgress(
''',
    '''                    if data.sourceFrame then
                        local progressCopied, textCopied = LegacyDurationDriver.MirrorProgress(
''',
    'duration onupdate mirror'
)
replace_once(
    '''                local progressCopied = false
                local resolver = DDingUI.TrackedAuraFrameResolver
                if frame and resolver and resolver.MirrorProgress then
                    progressCopied = resolver:MirrorProgress(
''',
    '''                local progressCopied = false
                if frame then
                    progressCopied = LegacyDurationDriver.MirrorProgress(
''',
    'initial progress mirror'
)

duration_pattern = re.compile(
    r'(?P<indent>[ \t]*)local durObj = C_UnitAuras\.GetAuraDuration\((?P<args>[^\n]+)\)\n'
    r'(?P=indent)if durObj then\n'
    r'(?P=indent)    local (?P<var>[A-Za-z_][A-Za-z0-9_]*) = durObj:GetRemainingDuration\(\)'
)


def duration_repl(match):
    indent = match.group('indent')
    args = match.group('args')
    var = match.group('var')
    return (
        f'{indent}local {var} = LegacyDurationDriver.GetRemainingDuration({args})\n'
        f'{indent}if {var} ~= nil then'
    )


text, duration_replacements = duration_pattern.subn(duration_repl, text)
assert duration_replacements == 8, f'GetAuraDuration replacements: expected 8, got {duration_replacements}'
text = text.replace('-- Duration 모드: C_UnitAuras.GetAuraDuration 사용', '-- Duration 모드: legacy duration driver 사용')

replace_slice(
    '''    if frame and frame.Cooldown then
        -- 3a. CDM 프레임 있음: SetCooldown 훅
''',
    '\n    -- CircularProgress 숨기기 (stacks 모드 잔재)\n',
    '''    LegacyDurationDriver.SyncRingCooldown(frame, bar.Cooldown, unit, auraInstanceID)

''',
    'ring cooldown sync'
)
text = text.replace(
    '    -- RING PROGRESS (CDM Cooldown 훅 방식)\n    -- CDM의 SetCooldown을 훅해서 우리 링과 동기화\n',
    '    -- RING PROGRESS -- compatibility fallback is synchronized by LegacyDurationDriver\n'
)

replace_once(
    '''            -- Duration data
            local expiresAt = nil
            if HasAuraInstanceID(auraInstanceID) then
                pcall(function()
                    local aData = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)
                    if aData and aData.expirationTime then expiresAt = aData.expirationTime end
                end)
            end
''',
    '''            -- Duration data -- compatibility fallback only
            local _, expiresAt = LegacyDurationDriver.ReadTiming(unit, auraInstanceID)
''',
    'ring duration text expiration'
)

replace_slice(
    '    -- Set cooldown swipe (duration display)\n',
    '    -- Set stack text\n',
    '''    -- Set cooldown swipe (legacy compatibility path only)
    if hasData and HasAuraInstanceID(auraInstanceID) then
        LegacyDurationDriver.SyncAuraCooldown(
            icon.Cooldown, icon, "_lastAuraInstanceID", unit, auraInstanceID
        )
    else
        LegacyDurationDriver.SyncAuraCooldown(
            icon.Cooldown, icon, "_lastAuraInstanceID", unit, nil
        )
    end

''',
    'icon cooldown swipe'
)

replace_once(
    '''        elseif hasData and not tracker.endBeforePlayed and HasAuraInstanceID(auraInstanceID) then
            pcall(function()
                local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)
                if auraData and auraData.expirationTime then
                    local timeLeft = auraData.expirationTime - now
                    if timeLeft > 0 and timeLeft <= soundEndBefore then
                        PlayTrackerSound(soundFile, soundChannel, soundCustomPath)
                        tracker.lastPlayTime = now
                        tracker.endBeforePlayed = true
                    end
                end
            end)
''',
    '''        elseif hasData and not tracker.endBeforePlayed and HasAuraInstanceID(auraInstanceID) then
            local timeLeft = LegacyDurationDriver.GetTimeLeft(unit, auraInstanceID, now)
            if timeLeft and timeLeft > 0 and timeLeft <= soundEndBefore then
                PlayTrackerSound(soundFile, soundChannel, soundCustomPath)
                tracker.lastPlayTime = now
                tracker.endBeforePlayed = true
            end
''',
    'sound end-before timing'
)

replace_once(
    '''        if hasData and HasAuraInstanceID(auraInstanceID) then
            pcall(function()
                local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)
                if auraData and auraData.expirationTime then
                    local timeLeft = auraData.expirationTime - GetTime()
                    if timeLeft > 0 then
                        displayText = string.format("%." .. durationDecimals .. "f", timeLeft)
                    else
                        displayText = "0"
                    end
                end
            end)
''',
    '''        if hasData and HasAuraInstanceID(auraInstanceID) then
            local timeLeft = LegacyDurationDriver.GetTimeLeft(unit, auraInstanceID, GetTime())
            if timeLeft then
                if timeLeft > 0 then
                    displayText = string.format("%." .. durationDecimals .. "f", timeLeft)
                else
                    displayText = "0"
                end
            end
''',
    'text mode duration'
)

assert text.count('C_UnitAuras.GetAuraDuration') == 0, 'direct GetAuraDuration remains'
assert text.count('GetCooldownTimes') == 0, 'direct GetCooldownTimes remains'
assert 'resolver:MirrorProgress' not in text, 'direct resolver MirrorProgress remains'
assert text.count('GetAuraDataByAuraInstanceID') == 3, text.count('GetAuraDataByAuraInstanceID')
assert text.count(':SetCooldown(') == 1, text.count(':SetCooldown(')
assert 'LegacyDurationDriver.SyncRingCooldown' in text
assert 'LegacyDurationDriver.ResolveDynamicDuration' in text
assert 'LegacyDurationDriver.GetRemainingDuration' in text

path.write_text(text, encoding='utf-8')
