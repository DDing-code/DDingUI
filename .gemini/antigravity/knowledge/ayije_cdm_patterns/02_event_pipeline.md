# Pattern 02: 이벤트 → 갱신 파이프라인 (C_Timer 없음)

## 핵심 아이디어
이벤트 핸들러에서 **직접 큐에 삽입**하고 OnUpdate 프로세서가 처리.
C_Timer.After() 로 클로저를 생성하지 않아 GC 압박 없음.

## 소스 위치
- `Ayije_CDM_/Core/TrackerCooldownWatcher.lua`
- `Ayije_CDM_/Core/Main.lua` 이벤트 등록 섹션

## 코드 패턴

```lua
-- ① UNIT_AURA → 직접 QueueViewer
CDM:RegisterUnitEvent("UNIT_AURA", "player", function(event, unit)
    CDM:QueueViewer(VIEWERS.BUFF, false)       -- 테이블 쓰기 1회
    CDM:QueueViewer(VIEWERS.BUFF_BAR, false)
end)

-- ② SPELL_UPDATE_COOLDOWN → 직접 QueueViewer
CDM:RegisterEvent("SPELL_UPDATE_COOLDOWN", function()
    CDM:QueueViewer(VIEWERS.ESSENTIAL)
    CDM:QueueViewer(VIEWERS.UTILITY)
end)

-- ③ 쿨다운 만료 감지: TrackerCooldownWatcher
-- OnCooldownIDSet 훅 + EvaluateRemainingDuration 커브 평가
-- (C_Timer.After로 만료 예약 안 함 — 커브로 실시간 평가)
local function OnCooldownDone(cdID, viewerName)
    CDM:QueueViewer(viewerName)   -- 만료 시 큐 삽입
end
```

## dirty flag + 단일 OnUpdate (P0 DDingUI 적용 패턴)

이벤트마다 새 C_Timer.After를 만드는 대신:

```lua
-- 이벤트 핸들러:
local viewerDirty = {}

hookFrame:SetScript("OnEvent", function()
    if not viewerDirty[viewerName] then
        viewerDirty[viewerName] = true
        -- OnUpdate 프로세서가 없으면 활성화
        if not processorActive then
            processorActive = true
            Processor:SetScript("OnUpdate", ProcessDirty)
        end
    end
end)

-- OnUpdate 프로세서:
local function ProcessDirty()
    local any = false
    for name in pairs(viewerDirty) do
        RescanViewer(name)
        viewerDirty[name] = nil
        any = true
        break  -- 1 프레임에 1개
    end
    if not any then
        processorActive = false
        Processor:SetScript("OnUpdate", nil)  -- 자신을 제거
    end
end
```

## C_Timer.After 방식과의 비교

| 항목 | C_Timer.After | dirty flag + OnUpdate |
|------|--------------|----------------------|
| 이벤트당 할당 | 클로저 1개 (GC 대상) | 0 (필드 쓰기만) |
| 딜레이 제어 | 명시적 (0.01~0.2초) | 다음 프레임 즉시 |
| 중복 방지 | `rescanPending` 플래그 | `dirty` 플래그 |
| 처리 보장 | C_Timer 큐 | OnUpdate 루프 |

## 주의: OnShow HookScript C_Timer 유지 여부

IconViewers의 OnShow 훅 내 `C_Timer.After(0.05, ...)` 는 유지해도 됨.
OnShow는 초기화 시 또는 DragonRiding 복귀 등 드물게 발생하므로 클로저 부담 미미.
