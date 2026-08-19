from pathlib import Path
import subprocess

PATH = Path('DDingUI/Modules/GroupSystem/FrameController.lua')
BASE = 'origin/agent/aura-style-migration'

# Restore the exact stacked-base blob and edit it line-by-line. FrameController
# historically contains mixed line endings, so normalizing the whole file makes
# GitHub report thousands of fake changed lines. Every untouched line below is
# kept byte-for-byte identical to the base blob.
base_bytes = subprocess.check_output(['git', 'show', f'{BASE}:{PATH.as_posix()}'])
base_text = base_bytes.decode('utf-8')
lines = base_text.splitlines(keepends=True)


def body(line):
    return line.rstrip('\r\n')


def ending(line):
    value = line[len(body(line)):]
    return value or '\n'


def new_line(value, reference):
    return value + ending(reference)


def exact_indices(value, start=0, end=None):
    if end is None:
        end = len(lines)
    return [i for i in range(start, end) if body(lines[i]) == value]


def unique_index(value, start=0, end=None, label=None):
    found = exact_indices(value, start, end)
    assert len(found) == 1, f'{label or value}: expected 1 match, got {len(found)}'
    return found[0]


def replace_line(index, value):
    lines[index] = new_line(value, lines[index])


def insert_after(index, values):
    ref = lines[index]
    lines[index + 1:index + 1] = [new_line(value, ref) for value in values]


def insert_before(index, values):
    ref = lines[index]
    lines[index:index] = [new_line(value, ref) for value in values]


def replace_range(start, end, values):
    ref = lines[start] if start < len(lines) else lines[start - 1]
    lines[start:end] = [new_line(value, ref) for value in values]


# Registry dependency.
i = unique_index('local CDMCompat = DDingUI.CDMCompat', label='CDMCompat local')
insert_after(i, [
    'local FrameRegistry = DDingUI.GroupCDMFrameRegistry',
    'if not FrameRegistry then',
    '    error("DDingUI: GroupCDMFrameRegistry must load before FrameController.lua")',
    'end',
])

# Parent-change diagnostics + conditional SetParent helper.
i = unique_index(
    'FrameController._diagCounters = { activeStateChanged = 0, cooldownIDSet = 0, poolRelease = 0 }',
    label='diagnostic counters',
)
replace_range(i, i + 1, [
    'FrameController._diagCounters = {',
    '    activeStateChanged = 0,',
    '    cooldownIDSet = 0,',
    '    poolRelease = 0,',
    '    registryScans = 0,',
    '    parentChanges = 0,',
    '    parentNoops = 0,',
    '}',
    '',
    'local function SetFrameParentIfNeeded(frame, parent)',
    '    if not frame or not parent or not frame.GetParent or not frame.SetParent then return false end',
    '    if frame:GetParent() == parent then',
    '        FrameController._diagCounters.parentNoops = FrameController._diagCounters.parentNoops + 1',
    '        return false',
    '    end',
    '    frame:SetParent(parent)',
    '    FrameController._diagCounters.parentChanges = FrameController._diagCounters.parentChanges + 1',
    '    return true',
    'end',
])

# Viewer references are registered as soon as they are discovered/replaced.
i = unique_index('            viewerRefs[def.globalName] = viewer', label='FindViewers assignment')
insert_after(i, ['            FrameRegistry:RegisterViewer(def.globalName, viewer)'])

i = unique_index(
    '        if currentViewer and currentViewer.itemFramePool then',
    label='RefreshViewerRefs viewer guard',
)
insert_after(i, ['            FrameRegistry:RegisterViewer(def.globalName, currentViewer)'])

# Remove only the unused runtime aura-probe helper family. Diagnostic slash
# commands intentionally keep their explicit C_UnitAuras probes.
start = unique_index('local function AddAuraCandidate(list, seen, value)', label='aura helper start')
end = unique_index('local function HideManagedBorderLayers(frame)', start=start + 1, label='aura helper end')
removed_bodies = [body(line) for line in lines[start:end]]
assert any(value.startswith('local function BuffFrameHasPlayerAura') for value in removed_bodies)
assert len(removed_bodies) < 100, f'unexpected aura helper block size: {len(removed_bodies)}'
del lines[start:end]

# Release hook immediately invalidates registry identity.
i = unique_index(
    '        hooksecurefunc(viewer.itemFramePool, "Release", function(_, frame)',
    label='pool release hook',
)
insert_after(i, ['            FrameRegistry:ReleaseFrame(frame, globalName)'])

# Reconcile hot path: consume registry snapshot instead of enumerating Blizzard
# itemFramePool every pass.
scan_start = unique_index('function FrameController:ScanCDMViewers()', label='ScanCDMViewers start')
scan_end = unique_index('-- 하위 호환 별칭', start=scan_start + 1, label='ScanCDMViewers end')

i = unique_index('    local previousCount = 0', scan_start, scan_end, 'scan previousCount')
insert_before(i, [
    '    FrameRegistry:Refresh(viewerRefs)',
    '    FrameController._diagCounters.registryScans = FrameController._diagCounters.registryScans + 1',
    '',
])
scan_end += 3

i = unique_index('        if shouldScan and viewer.itemFramePool then', scan_start, scan_end, 'scan viewer guard')
replace_line(i, '        if shouldScan then')

i = unique_index(
    '            for icon in viewer.itemFramePool:EnumerateActive() do',
    scan_start,
    scan_end,
    'scan pool loop',
)
replace_line(i, '            for registeredCooldownID, icon in pairs(FrameRegistry:GetFrames(globalName)) do')
next_i = i + 1
assert body(lines[next_i]) == '                local cooldownID = GetSafeFrameCooldownID(icon)'
replace_line(next_i, '                local cooldownID = GetSafeFrameCooldownID(icon, registeredCooldownID)')

# Preserve existing ownership model but skip redundant SetParent calls.
parent_patterns = {
    'self:SetParent(UIParent)': 'SetFrameParentIfNeeded(self, UIParent)',
    'frame:SetParent(UIParent)': 'SetFrameParentIfNeeded(frame, UIParent)',
    'icon:SetParent(UIParent)': 'SetFrameParentIfNeeded(icon, UIParent)',
    'frame:SetParent(orig.parent)': 'SetFrameParentIfNeeded(frame, orig.parent)',
}
counts = {key: 0 for key in parent_patterns}
for idx, line in enumerate(lines):
    value = body(line)
    changed = value
    for old, new in parent_patterns.items():
        if old in changed:
            counts[old] += changed.count(old)
            changed = changed.replace(old, new)
    if changed != value:
        replace_line(idx, changed)
for old, count in counts.items():
    assert count > 0, f'missing parent pattern: {old}'

# Layout recovery uses registry snapshot.
hook_start = unique_index('-- [HOOK D] 뷰어별 Layout/Show/Hide', label='layout hook start')
hook_end = unique_index('-- [CDM 패턴 C] Provisional Reparent', start=hook_start + 1, label='layout hook end')
candidates = [
    i for i in range(hook_start, hook_end)
    if 'for icon in viewer.itemFramePool:EnumerateActive() do' in body(lines[i])
]
assert len(candidates) == 1, f'layout pool loop: expected 1, got {len(candidates)}'
i = candidates[0]
indent = body(lines[i]).split('for icon', 1)[0]
replace_line(i, indent + 'for _, icon in pairs(FrameRegistry:GetFrames(FrameRegistry:ResolveViewerName(viewer) or globalName)) do')

# Reactive acquire/id hooks.
i = unique_index(
    '                FrameController:_ResetAcquiredCooldownFrame(frame)',
    label='OnAcquire reset',
)
insert_after(i, ['                FrameRegistry:Acquire(viewer, frame)'])

i = unique_index(
    '            local prevCdID = itemFrame._ddLastCooldownID',
    label='SetCooldownID previous id',
)
insert_before(i, ['            FrameRegistry:TrackFrame(itemFrame, safeCooldownID)'])

# Initial tracked-aura setup uses bounded registry bootstrap rather than direct
# pool enumeration.
sequence = [
    '    for _, viewerName in ipairs({ "BuffIconCooldownViewer", "BuffBarCooldownViewer" }) do',
    '        local viewer = _G[viewerName]',
    '        local pool = viewer and viewer.itemFramePool',
    '        if pool and pool.EnumerateActive then',
    '            for frame in pool:EnumerateActive() do',
    '                FrameController:_TrackAuraFrame(frame)',
    '            end',
    '        end',
    '    end',
]
starts = []
for idx in range(0, len(lines) - len(sequence) + 1):
    if [body(line) for line in lines[idx:idx + len(sequence)]] == sequence:
        starts.append(idx)
assert len(starts) == 1, f'initial aura pool block: expected 1, got {len(starts)}'
i = starts[0]
replace_range(i, i + len(sequence), [
    '    FrameRegistry:Bootstrap(viewerRefs)',
    '    for _, viewerName in ipairs({ "BuffIconCooldownViewer", "BuffBarCooldownViewer" }) do',
    '        for _, frame in pairs(FrameRegistry:GetFrames(viewerName)) do',
    '            FrameController:_TrackAuraFrame(frame)',
    '        end',
    '    end',
])

# Edit-mode click setup/teardown also consume registry snapshots.
for function_name, next_marker in [
    ('function FrameController:EnableEditModeClicks()', 'function FrameController:DisableEditModeClicks()'),
    ('function FrameController:DisableEditModeClicks()', '-- ============================================================\n-- 그룹 선택 팝업'),
]:
    start_idx = unique_index(function_name, label=function_name)
    if '\n' in next_marker:
        marker_first = next_marker.split('\n', 1)[0]
        end_idx = unique_index(marker_first, start=start_idx + 1, label='edit marker')
        # First separator appears in several places; advance to the one whose
        # next line is the expected popup title.
        expected_next = next_marker.split('\n', 1)[1]
        matches = []
        for candidate in exact_indices(marker_first, start_idx + 1):
            if candidate + 1 < len(lines) and body(lines[candidate + 1]) == expected_next:
                matches.append(candidate)
        assert len(matches) == 1, f'popup marker: expected 1, got {len(matches)}'
        end_idx = matches[0]
    else:
        end_idx = unique_index(next_marker, start=start_idx + 1, label=next_marker)
    candidates = [
        i for i in range(start_idx, end_idx)
        if 'for icon in viewer.itemFramePool:EnumerateActive() do' in body(lines[i])
    ]
    assert len(candidates) == 1, f'{function_name} pool loop: expected 1, got {len(candidates)}'
    idx = candidates[0]
    value = body(lines[idx])
    indent = value.split('for icon', 1)[0]
    replace_line(idx, indent + 'for _, icon in pairs(FrameRegistry:GetFrames(globalName)) do')

# Final invariants are checked on normalized line bodies only; original line
# endings remain untouched on every unchanged line.
normalized = '\n'.join(body(line) for line in lines)
scan = normalized[normalized.index('function FrameController:ScanCDMViewers()'):normalized.index('-- 하위 호환 별칭')]
layout = normalized[normalized.index('-- [HOOK D] 뷰어별 Layout/Show/Hide'):normalized.index('-- [CDM 패턴 C] Provisional Reparent')]
edit = normalized[normalized.index('function FrameController:EnableEditModeClicks()'):normalized.index('-- 그룹 선택 팝업')]
assert ':EnumerateActive()' not in scan
assert ':EnumerateActive()' not in layout
assert ':EnumerateActive()' not in edit
assert 'FrameRegistry:Refresh(viewerRefs)' in scan
assert 'FrameRegistry:Acquire(viewer, frame)' in normalized
assert 'FrameRegistry:ReleaseFrame(frame, globalName)' in normalized
assert 'FrameRegistry:TrackFrame(itemFrame, safeCooldownID)' in normalized
assert 'local function BuffFrameHasPlayerAura' not in normalized
assert 'SetFrameParentIfNeeded' in normalized
assert 'frame:SetParent(UIParent)' not in normalized
assert 'self:SetParent(UIParent)' not in normalized
assert 'icon:SetParent(UIParent)' not in normalized

PATH.write_bytes(''.join(lines).encode('utf-8'))
