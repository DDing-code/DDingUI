from pathlib import Path
import re

path = Path('DDingUI/Modules/GroupSystem/FrameController.lua')
raw = path.read_bytes()
eol = '\r\n' if b'\r\n' in raw else '\n'
text = raw.decode('utf-8').replace('\r\n', '\n')


def replace_once(old, new, label):
    global text
    count = text.count(old)
    assert count == 1, f'{label}: expected 1 match, got {count}'
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
    'parent helper',
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

text, n = re.subn(
    r'\nlocal function AddAuraCandidate\(list, seen, value\).*?\nlocal function HideManagedBorderLayers\(frame\)',
    '\nlocal function HideManagedBorderLayers(frame)',
    text,
    count=1,
    flags=re.S,
)
assert n == 1, f'dead aura helper removal: expected 1, got {n}'

replace_once(
    '        hooksecurefunc(viewer.itemFramePool, "Release", function(_, frame)\n            if CDMCompat then\n',
    '        hooksecurefunc(viewer.itemFramePool, "Release", function(_, frame)\n'
    '            FrameRegistry:ReleaseFrame(frame, globalName)\n'
    '            if CDMCompat then\n',
    'pool release registry',
)

start = text.index('function FrameController:ScanCDMViewers()')
end = text.index('-- 하위 호환 별칭', start)
scan = text[start:end]
old = (
    'function FrameController:ScanCDMViewers()\n'
    '    if IsCooldownViewerSettingsOpen() then\n'
    '        return false\n'
    '    end\n\n'
    '    local previousCount = 0\n'
)
new = (
    'function FrameController:ScanCDMViewers()\n'
    '    if IsCooldownViewerSettingsOpen() then\n'
    '        return false\n'
    '    end\n\n'
    '    FrameRegistry:Refresh(viewerRefs)\n'
    '    FrameController._diagCounters.registryScans = FrameController._diagCounters.registryScans + 1\n\n'
    '    local previousCount = 0\n'
)
assert scan.count(old) == 1, 'scan prelude mismatch'
scan = scan.replace(old, new, 1)
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
assert scan.count(old_loop) == 1, 'scan pool loop mismatch'
scan = scan.replace(old_loop, new_loop, 1)
scan = scan.replace(
    '-- 매 Reconcile마다 EnumerateActive() → idIconMap 재구축 → 전체 재배치.\n'
    '-- 이전 상태와 비교하지 않으므로 고아 개념 자체가 불필요.\n',
    '-- Reconcile은 reactive registry snapshot으로 idIconMap을 재구축합니다.\n'
    '-- Blizzard pool 열거는 scanner bootstrap fallback에서만 허용합니다.\n',
)
assert 'EnumerateActive()' not in scan, 'ScanCDMViewers still enumerates Blizzard pools'
text = text[:start] + scan + text[end:]

parent_replacements = {
    'self:SetParent(UIParent)': 'SetFrameParentIfNeeded(self, UIParent)',
    'frame:SetParent(UIParent)': 'SetFrameParentIfNeeded(frame, UIParent)',
    'icon:SetParent(UIParent)': 'SetFrameParentIfNeeded(icon, UIParent)',
    'frame:SetParent(orig.parent)': 'SetFrameParentIfNeeded(frame, orig.parent)',
}
for old_parent, new_parent in parent_replacements.items():
    count = text.count(old_parent)
    assert count > 0, f'parent replacement missing: {old_parent}'
    text = text.replace(old_parent, new_parent)

hook_start = text.index('-- [HOOK D] 뷰어별 Layout/Show/Hide')
hook_end = text.index('-- [CDM 패턴 C] Provisional Reparent', hook_start)
hook_region = text[hook_start:hook_end]
old_layout_loop = '                        for icon in viewer.itemFramePool:EnumerateActive() do\n'
new_layout_loop = (
    '                        for _, icon in pairs(FrameRegistry:GetFrames('
    'FrameRegistry:ResolveViewerName(viewer) or globalName)) do\n'
)
assert hook_region.count(old_layout_loop) == 1, 'layout pool loop mismatch'
hook_region = hook_region.replace(old_layout_loop, new_layout_loop, 1)
assert 'EnumerateActive()' not in hook_region, 'Layout hook still enumerates pool'
text = text[:hook_start] + hook_region + text[hook_end:]

replace_once(
    '                FrameController:_ResetAcquiredCooldownFrame(frame)\n'
    '                if CDMCompat then\n',
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
assert text.count(initial_old) == 1, 'initial aura tracking pool loop mismatch'
text = text.replace(initial_old, initial_new, 1)

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

assert 'C_UnitAuras.GetPlayerAuraBySpellID' not in text, 'unused direct aura probe remains'
assert 'frame:SetParent(UIParent)' not in text, 'unconditional frame:SetParent(UIParent) remains'
assert 'self:SetParent(UIParent)' not in text, 'unconditional self:SetParent(UIParent) remains'
assert 'icon:SetParent(UIParent)' not in text, 'unconditional icon:SetParent(UIParent) remains'

path.write_bytes(text.replace('\n', eol).encode('utf-8'))

registry_path = Path('DDingUI/Modules/GroupSystem/CDMFrameRegistry.lua')
reg = registry_path.read_text(encoding='utf-8')
old = '''local function TrackScannerFrame(self, viewerName, frame, cooldownID)
    if not frame or not IsUsableID(cooldownID) then return 0 end
    local viewer = _G[viewerName]
    if viewer then self:RegisterViewer(viewerName, viewer) end
    return self:TrackFrame(frame, cooldownID, viewerName) and 1 or 0
end'''
new = '''local function TrackScannerFrame(self, viewerName, frame, cooldownID)
    if not frame or not IsUsableID(cooldownID) then return 0 end
    local viewer = _G[viewerName]
    if viewer then self:RegisterViewer(viewerName, viewer) end
    local existing = EnsureViewerTable(viewerName)[cooldownID]
    if existing and existing ~= frame then
        return 0
    end
    return self:TrackFrame(frame, cooldownID, viewerName) and 1 or 0
end'''
assert reg.count(old) == 1, 'scanner precedence patch mismatch'
registry_path.write_text(reg.replace(old, new, 1), encoding='utf-8')
