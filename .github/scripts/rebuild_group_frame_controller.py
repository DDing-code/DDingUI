from pathlib import Path
import re
import subprocess

PATH = Path('DDingUI/Modules/GroupSystem/FrameController.lua')
BASE = 'origin/agent/aura-style-migration'

# Restore the exact base blob first. This avoids accidental whole-file EOL churn.
base_bytes = subprocess.check_output(['git', 'show', f'{BASE}:{PATH.as_posix()}'])
PATH.write_bytes(base_bytes)

eol = '\r\n' if b'\r\n' in base_bytes else '\n'
text = base_bytes.decode('utf-8').replace('\r\n', '\n').replace('\r', '\n')


def replace_once(old, new, label):
    global text
    count = text.count(old)
    assert count == 1, f'{label}: expected exactly 1 match, got {count}'
    text = text.replace(old, new, 1)


replace_once(
    'local CDMCompat = DDingUI.CDMCompat\n',
    'local CDMCompat = DDingUI.CDMCompat\n'
    'local FrameRegistry = DDingUI.GroupCDMFrameRegistry\n'
    'if not FrameRegistry then\n'
    '    error("DDingUI: GroupCDMFrameRegistry must load before FrameController.lua")\n'
    'end\n',
    'registry local',
)

replace_once(
    'FrameController._diagCounters = { activeStateChanged = 0, cooldownIDSet = 0, poolRelease = 0 }\n',
    'FrameController._diagCounters = {\n'
    '    activeStateChanged = 0,\n'
    '    cooldownIDSet = 0,\n'
    '    poolRelease = 0,\n'
    '    registryScans = 0,\n'
    '    parentChanges = 0,\n'
    '    parentNoops = 0,\n'
    '}\n\n'
    'local function SetFrameParentIfNeeded(frame, parent)\n'
    '    if not frame or not parent or not frame.GetParent or not frame.SetParent then return false end\n'
    '    if frame:GetParent() == parent then\n'
    '        FrameController._diagCounters.parentNoops = FrameController._diagCounters.parentNoops + 1\n'
    '        return false\n'
    '    end\n'
    '    frame:SetParent(parent)\n'
    '    FrameController._diagCounters.parentChanges = FrameController._diagCounters.parentChanges + 1\n'
    '    return true\n'
    'end\n',
    'conditional parent helper',
)

replace_once(
    '            viewerRefs[def.globalName] = viewer\n            if CDMCompat then CDMCompat:TrackViewerPool(viewer) end\n',
    '            viewerRefs[def.globalName] = viewer\n'
    '            FrameRegistry:RegisterViewer(def.globalName, viewer)\n'
    '            if CDMCompat then CDMCompat:TrackViewerPool(viewer) end\n',
    'FindViewers registry',
)

replace_once(
    '        if currentViewer and currentViewer.itemFramePool then\n            if CDMCompat then CDMCompat:TrackViewerPool(currentViewer) end\n',
    '        if currentViewer and currentViewer.itemFramePool then\n'
    '            FrameRegistry:RegisterViewer(def.globalName, currentViewer)\n'
    '            if CDMCompat then CDMCompat:TrackViewerPool(currentViewer) end\n',
    'RefreshViewerRefs registry',
)

# Remove only the unused runtime aura-probe helper family. Diagnostic slash
# commands below intentionally retain their explicit probes.
start = text.index('local function AddAuraCandidate(')
end = text.index('local function HideManagedBorderLayers(', start)
removed = text[start:end]
assert 'local function BuffFrameHasPlayerAura' in removed
assert len(removed.splitlines()) < 100, f'unexpected aura helper block size: {len(removed.splitlines())}'
text = text[:start] + text[end:]

replace_once(
    '        hooksecurefunc(viewer.itemFramePool, "Release", function(_, frame)\n            if CDMCompat then\n',
    '        hooksecurefunc(viewer.itemFramePool, "Release", function(_, frame)\n'
    '            FrameRegistry:ReleaseFrame(frame, globalName)\n'
    '            if CDMCompat then\n',
    'pool release registry',
)

# Reconcile hot path: registry snapshot instead of Blizzard pool walk.
scan_start = text.index('function FrameController:ScanCDMViewers()')
scan_end = text.index('-- 하위 호환 별칭', scan_start)
scan = text[scan_start:scan_end]
old_prelude = (
    'function FrameController:ScanCDMViewers()\n'
    '    if IsCooldownViewerSettingsOpen() then\n'
    '        return false\n'
    '    end\n\n'
    '    local previousCount = 0\n'
)
new_prelude = (
    'function FrameController:ScanCDMViewers()\n'
    '    if IsCooldownViewerSettingsOpen() then\n'
    '        return false\n'
    '    end\n\n'
    '    FrameRegistry:Refresh(viewerRefs)\n'
    '    FrameController._diagCounters.registryScans = FrameController._diagCounters.registryScans + 1\n\n'
    '    local previousCount = 0\n'
)
assert scan.count(old_prelude) == 1
scan = scan.replace(old_prelude, new_prelude, 1)
assert scan.count('if shouldScan and viewer.itemFramePool then') == 1
scan = scan.replace('if shouldScan and viewer.itemFramePool then', 'if shouldScan then', 1)
old_loop = (
    '            for icon in viewer.itemFramePool:EnumerateActive() do\n'
    '                local cooldownID = GetSafeFrameCooldownID(icon)\n'
)
new_loop = (
    '            for registeredCooldownID, icon in pairs(FrameRegistry:GetFrames(globalName)) do\n'
    '                local cooldownID = GetSafeFrameCooldownID(icon, registeredCooldownID)\n'
)
assert scan.count(old_loop) == 1
scan = scan.replace(old_loop, new_loop, 1)
assert ':EnumerateActive()' not in scan
text = text[:scan_start] + scan + text[scan_end:]

# Preserve current reparent ownership model, but never call SetParent when the
# frame already has the desired parent.
for old_parent, new_parent in {
    'self:SetParent(UIParent)': 'SetFrameParentIfNeeded(self, UIParent)',
    'frame:SetParent(UIParent)': 'SetFrameParentIfNeeded(frame, UIParent)',
    'icon:SetParent(UIParent)': 'SetFrameParentIfNeeded(icon, UIParent)',
    'frame:SetParent(orig.parent)': 'SetFrameParentIfNeeded(frame, orig.parent)',
}.items():
    count = text.count(old_parent)
    assert count > 0, f'missing parent pattern: {old_parent}'
    text = text.replace(old_parent, new_parent)

# Layout recovery hot path.
hook_start = text.index('-- [HOOK D] 뷰어별 Layout/Show/Hide')
hook_end = text.index('-- [CDM 패턴 C] Provisional Reparent', hook_start)
hook_region = text[hook_start:hook_end]
old_layout_loop = '                        for icon in viewer.itemFramePool:EnumerateActive() do\n'
new_layout_loop = (
    '                        for _, icon in pairs(FrameRegistry:GetFrames('
    'FrameRegistry:ResolveViewerName(viewer) or globalName)) do\n'
)
assert hook_region.count(old_layout_loop) == 1
hook_region = hook_region.replace(old_layout_loop, new_layout_loop, 1)
assert ':EnumerateActive()' not in hook_region
text = text[:hook_start] + hook_region + text[hook_end:]

# Reactive identity hooks.
replace_once(
    '                FrameController:_ResetAcquiredCooldownFrame(frame)\n                if CDMCompat then\n',
    '                FrameController:_ResetAcquiredCooldownFrame(frame)\n'
    '                FrameRegistry:Acquire(viewer, frame)\n'
    '                if CDMCompat then\n',
    'OnAcquire registry',
)

replace_once(
    '            if not IsSafeNumber(safeCooldownID) then\n'
    '                ScheduleReconcile(CONFIG.DEBOUNCE_NORMAL)\n'
    '                return\n'
    '            end\n'
    '            local prevCdID = itemFrame._ddLastCooldownID\n',
    '            if not IsSafeNumber(safeCooldownID) then\n'
    '                ScheduleReconcile(CONFIG.DEBOUNCE_NORMAL)\n'
    '                return\n'
    '            end\n'
    '            FrameRegistry:TrackFrame(itemFrame, safeCooldownID)\n'
    '            local prevCdID = itemFrame._ddLastCooldownID\n',
    'SetCooldownID registry',
)

# Initial BuffIcon/BuffBar tracking no longer walks Blizzard pools directly.
initial_old = (
    '    for _, viewerName in ipairs({ "BuffIconCooldownViewer", "BuffBarCooldownViewer" }) do\n'
    '        local viewer = _G[viewerName]\n'
    '        local pool = viewer and viewer.itemFramePool\n'
    '        if pool and pool.EnumerateActive then\n'
    '            for frame in pool:EnumerateActive() do\n'
    '                FrameController:_TrackAuraFrame(frame)\n'
    '            end\n'
    '        end\n'
    '    end\n\n'
    '    state.hooksInstalled = true\n'
)
initial_new = (
    '    FrameRegistry:Bootstrap(viewerRefs)\n'
    '    for _, viewerName in ipairs({ "BuffIconCooldownViewer", "BuffBarCooldownViewer" }) do\n'
    '        for _, frame in pairs(FrameRegistry:GetFrames(viewerName)) do\n'
    '            FrameController:_TrackAuraFrame(frame)\n'
    '        end\n'
    '    end\n\n'
    '    state.hooksInstalled = true\n'
)
assert text.count(initial_old) == 1
text = text.replace(initial_old, initial_new, 1)

# Edit-mode click setup/teardown uses the same registry snapshot.
edit_start = text.index('function FrameController:EnableEditModeClicks()')
edit_end = text.index('function FrameController:DisableEditModeClicks()', edit_start)
edit = text[edit_start:edit_end]
assert edit.count('for icon in viewer.itemFramePool:EnumerateActive() do') == 1
edit = edit.replace(
    'for icon in viewer.itemFramePool:EnumerateActive() do',
    'for _, icon in pairs(FrameRegistry:GetFrames(globalName)) do',
    1,
)
text = text[:edit_start] + edit + text[edit_end:]

disable_start = text.index('function FrameController:DisableEditModeClicks()')
disable_end = text.index('-- ============================================================\n-- 그룹 선택 팝업', disable_start)
disable = text[disable_start:disable_end]
assert disable.count('for icon in viewer.itemFramePool:EnumerateActive() do') == 1
disable = disable.replace(
    'for icon in viewer.itemFramePool:EnumerateActive() do',
    'for _, icon in pairs(FrameRegistry:GetFrames(globalName)) do',
    1,
)
text = text[:disable_start] + disable + text[disable_end:]

# Final static invariants.
scan = text[text.index('function FrameController:ScanCDMViewers()'):text.index('-- 하위 호환 별칭')]
layout = text[text.index('-- [HOOK D] 뷰어별 Layout/Show/Hide'):text.index('-- [CDM 패턴 C] Provisional Reparent')]
edit = text[text.index('function FrameController:EnableEditModeClicks()'):text.index('-- ============================================================\n-- 그룹 선택 팝업')]
assert ':EnumerateActive()' not in scan
assert ':EnumerateActive()' not in layout
assert ':EnumerateActive()' not in edit
assert 'FrameRegistry:Refresh(viewerRefs)' in scan
assert 'FrameRegistry:Acquire(viewer, frame)' in text
assert 'FrameRegistry:ReleaseFrame(frame, globalName)' in text
assert 'FrameRegistry:TrackFrame(itemFrame, safeCooldownID)' in text
assert 'local function BuffFrameHasPlayerAura' not in text
assert 'SetFrameParentIfNeeded' in text
assert 'frame:SetParent(UIParent)' not in text
assert 'self:SetParent(UIParent)' not in text
assert 'icon:SetParent(UIParent)' not in text

PATH.write_bytes(text.replace('\n', eol).encode('utf-8'))
