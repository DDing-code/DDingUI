# Pattern 01: 단일 Updater + QueueProcessor

## 핵심 아이디어
"필요할 때만 켜고, 완료 즉시 끄는" 단일 OnUpdate 프레임.
모든 뷰어 갱신 요청은 딕셔너리 큐(테이블 필드 1개)로 수집하고, 단일 프로세서가 처리.

## 소스 위치
- `Ayije_CDM_/Core/Main.lua` L355~410

## 코드 패턴

```lua
-- ① 단일 공유 Updater 프레임
local Updater = CreateFrame("Frame")
local updaterActive = false

-- ② 큐: { [viewerName] = version } 딕셔너리
-- 갱신 요청은 필드 쓰기 1회, 클로저/C_Timer 생성 없음
CDM.queue = {}

-- ③ 갱신 요청 API
function CDM:QueueViewer(name, immediate, version)
    local qv = ...
    self.queue[name] = qv           -- O(1) 테이블 쓰기
    if not updaterActive then
        updaterActive = true
        Updater:SetScript("OnUpdate", QueueProcessor)  -- 필요할 때만 ON
    end
end

-- ④ 처리기: 1 프레임에 1 뷰어만 처리, 큐 비면 자신을 제거
local function QueueProcessor()
    if not next(CDM.queue) then
        updaterActive = false
        Updater:SetScript("OnUpdate", nil)   -- 큐 비면 즉시 OFF
        return
    end
    for name, version in pairs(CDM.queue) do
        local v = _G[name]
        if v then CDM:ForceReanchor(v) end
        CDM.queue[name] = nil
        break  -- 1 프레임에 1 뷰어만 (부하 분산)
    end
end

-- ⑤ 전투 중 갱신 큐잉 (Taint 방어)
CDM.combatDirtyViewers = {}

-- 전투 중 갱신 요청 시:
if InCombatLockdown() then
    CDM.combatDirtyViewers[viewerName] = true
    return
end

-- 전투 종료 시 일괄 처리:
CDM:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    local dirty = CDM.combatDirtyViewers
    if not next(dirty) then return end
    for vName in pairs(dirty) do
        CDM:QueueViewer(vName)
    end
    wipe(dirty)
end)
```

## DDingUI 적용 시 주의사항

- `FrameController.pollingFrame`의 burst 모드를 이 패턴으로 대체 가능
- 단, DDingUI는 GroupRenderer.UpdateGroup 비용이 크므로
  뷰어 단위가 아닌 dirty group 단위 큐로 설계 필요
- `combatDirtyViewers` → DDingUI의 `_postCombatQueue`와 동일 역할
  (이미 존재하나 실제 활용도 확인 필요)

## 핵심 이점

| 항목 | 이전 (C_Timer 방식) | Ayije 방식 |
|------|-------------------|-----------|
| 이벤트당 할당 | 클로저 1~2개 | 0 (테이블 쓰기만) |
| 동시 OnUpdate | 뷰어 수만큼 | **항상 1개** |
| 부하 분산 | 없음 (동시 처리) | 프레임당 1 뷰어씩 |
