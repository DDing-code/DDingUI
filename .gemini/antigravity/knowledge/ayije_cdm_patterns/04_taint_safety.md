# Pattern 04: Taint 방어 패턴

## 핵심 아이디어
WoW 12.0+에서 secure frame의 특정 필드(cooldownID, auraSpellID 등)는
"secret value"로 보호되어 addon에서 읽으면 Taint 발생.
Ayije는 4가지 레이어로 전투 중 Taint를 방어.

## 소스 위치
- `Ayije_CDM_/Core/Main.lua` (combatDirtyViewers, InCombatLockdown 가드)
- `Ayije_CDM_/Core/Init.lua` (GetAuraSpellID 메서드, weak-table)
- `Ayije_CDM_/Buffs.lua` (IsShown() 기반 필터)

## Taint 발생 필드 목록

| 필드 | 타입 | 안전한 접근법 |
|------|------|------------|
| `frame.cooldownID` | secret number | `pcall` 또는 캐시된 ID 사용 |
| `frame.auraSpellID` | secret number | `frame:GetAuraSpellID()` 메서드 사용 |
| `frame.auraInstanceID` | secret number | 존재 여부만 체크 (`HasAuraInstanceID`) |
| `frame.allowAvailableAlert` | secret boolean | `pcall` + false로 교체 |
| `frame.cooldownInfo` | secure table | `pcall(frame.GetCooldownInfo, frame)` |

## 패턴 1: IsShown() 기반 필터 (Ayije Buffs.lua L265)

```lua
-- CDM이 Show한 아이콘만 신뢰: cooldownID 접근 없이 가시성만 체크
for icon in viewer.itemFramePool:EnumerateActive() do
    if icon:IsShown() then      -- ← Taint-safe: IsShown()은 보호되지 않음
        -- 안전하게 처리
    end
end
```

## 패턴 2: GetAuraSpellID() 메서드 (Ayije Init.lua)

```lua
-- CDM 프레임에 래퍼 메서드 추가 (secure 환경에서 실행되므로 Taint 없음)
-- secret value인 auraSpellID를 addon이 읽는 대신
-- CDM 자신이 제공하는 메서드를 통해 안전하게 접근
local spellID = frame:GetAuraSpellID()    -- pcall 불필요
-- vs DDingUI 방식:
local ok, spellID = pcall(function() return frame.auraSpellID end)  -- pcall 필요
```

## 패턴 3: 전투 중 갱신 큐잉 (combatDirtyViewers)

```lua
function CDM:QueueViewer(name, ...)
    if InCombatLockdown() then
        self.combatDirtyViewers[name] = true   -- 갱신 미뤄두기
        return
    end
    self.queue[name] = ...
    -- OnUpdate 활성화
end

-- 전투 종료 후 일괄 처리
CDM:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    for vName in pairs(CDM.combatDirtyViewers) do
        CDM:QueueViewer(vName)
    end
    wipe(CDM.combatDirtyViewers)
end)
```

## 패턴 4: weak-table로 커스텀 데이터 격리

```lua
-- Blizzard secure frame에 직접 필드 쓰지 않음 → Taint 전파 방지
-- weak-table을 별도로 두고 frame을 키로 사용
local viewerState = setmetatable({}, { __mode = "k" })

-- 읽기/쓰기:
viewerState[frame].someProp = value     -- frame에 직접 쓰지 않음
-- DDingUI도 동일 패턴 사용 (IconViewers._viewerState)
```

## 패턴 5: issecretvalue 가드 (DDingUI 확장)

```lua
-- Ayije는 GetAuraSpellID()로 회피
-- DDingUI는 issecretvalue() API로 직접 체크 (WoW 12.0.1+ 제공)
local function IsSafeNumber(val)
    if val == nil then return false end
    if issecretvalue and issecretvalue(val) then return false end
    return type(val) == "number" and val == val   -- NaN 체크
end
```

## DDingUI 적용 포인트

- `FrameController.ScanCDMViewers`에서 `icon.cooldownID` 접근 시
  이미 `pcall` 사용 중이나, `frame:GetAuraSpellID()` 메서드가 있다면 pcall 불필요
- `iconSpellNameMap` 캐시 덕분에 전투 중 재조회 없이 분류 가능
- `_postCombatQueue`가 `combatDirtyViewers`와 동일 역할이나 실제 사용 여부 점검 필요
