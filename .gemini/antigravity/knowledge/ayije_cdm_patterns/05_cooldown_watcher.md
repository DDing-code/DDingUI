# Pattern 05: TrackerCooldownWatcher — 이벤트 기반 쿨다운 추적

## 핵심 아이디어
OnUpdate 폴링으로 쿨다운 만료를 감지하는 대신,
`SPELL_UPDATE_COOLDOWN` 이벤트 + `C_CurveUtil` 기반 평가로
IsVisible() / 폴링 없이 정확한 쿨다운 상태를 추적.

## 소스 위치
- `Ayije_CDM_/Core/TrackerCooldownWatcher.lua`

## 쿨다운 상태 평가 아키텍처

```
SPELL_UPDATE_COOLDOWN 이벤트
  → TrackerCooldownWatcher:OnCooldownUpdate()
  → frame:EvaluateRemainingDuration()           ← CDM 제공 안전 메서드
  → _DesaturationCurve:Evaluate(remaining)      ← C_CurveUtil 평가
  → desaturate / gcd-filter 상태 결정
  → CDM:QueueViewer(viewerName)                 ← 필요 시만 큐 삽입
```

## 코드 패턴

```lua
-- TrackerCooldownWatcher.lua:

local watcher = {}

-- ① SPELL_UPDATE_COOLDOWN 이벤트 등록
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
eventFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
eventFrame:SetScript("OnEvent", function(_, event)
    watcher:OnCooldownUpdate(event)
end)

-- ② 쿨다운 상태 평가 (폴링 없음)
function watcher:OnCooldownUpdate(event)
    for cdID, frame in pairs(trackedFrames) do
        local remaining = frame:EvaluateRemainingDuration()

        -- C_CurveUtil 기반 상태 결정 (IsVisible 대체)
        local isGCDOnly = _GCDFilterCurve:Evaluate(remaining) > 0.5
        local shouldDesaturate = (remaining <= 0) or isGCDOnly

        -- 상태 변경 시에만 갱신 요청 (불필요한 QueueViewer 방지)
        if shouldDesaturate ~= frame._lastDesaturated then
            frame._lastDesaturated = shouldDesaturate
            -- SetDesaturation (float) — SetDesaturated(bool) 대신
            frame:SetDesaturation(shouldDesaturate and 1.0 or 0.0)
            CDM:QueueViewer(frame._viewerName)
        end
    end
end

-- ③ EvaluateRemainingDuration — CDM 제공 안전 메서드
-- (secret value인 쿨다운 시간을 addon 측에서 직접 읽지 않음)
-- frame:EvaluateRemainingDuration() → number (초, secret-safe)
```

## _DesaturationCurve 와 _GCDFilterCurve 정의

```lua
-- Constants.lua:
-- 쿨다운 없음(0초) → desaturate=true, 쿨다운 있음 → desaturate=false
_DesaturationCurve = C_CurveUtil.CreateCurve({
    { x = 0.0,  y = 1.0 },   -- remaining=0: desaturate
    { x = 0.05, y = 0.0 },   -- remaining>0.05: color
})

-- GCD 길이(≤1.5초) 이하인 경우 GCD 필터링
_GCDFilterCurve = C_CurveUtil.CreateCurve({
    { x = 0.0,  y = 1.0 },
    { x = 1.5,  y = 1.0 },   -- 1.5초 이하: GCD로 간주
    { x = 1.51, y = 0.0 },   -- 1.51초 이상: 실제 쿨다운
})
```

## DDingUI에 이미 이식된 부분 (이전 세션 작업)

- `Toolkit.lua`: `_DesaturationCurve`, `_GCDFilterCurve` 전역 정의 완료
- `CustomIcons.lua`: `IsCooldownFrameActive(IsVisible)` → `EvaluateRemainingDuration()` 교체 완료
- `FrameController.lua`: `SPELL_UPDATE_COOLDOWN` 이벤트 등록 완료

## 남은 적용 포인트

- `GroupRenderer.UpdateGroup` 내 아이콘별 쿨다운 상태 체크:
  현재 `CooldownFrame:IsVisible()` 사용 부분을 커브 평가로 교체 고려
- `IconViewers.RescanViewer` 호출 조건:
  상태 변경 시에만 호출하도록 이전 상태 캐시(`_lastDesaturated`) 추가

## IsVisible() 사용 금지 이유

```lua
-- ❌ 불안정: 레이아웃 업데이트 중 false 반환 가능 → 깜빡임
if frame.CooldownFrame:IsVisible() then

-- ✅ 안정: 남은 시간으로 직접 평가
local remaining = frame:EvaluateRemainingDuration()
if remaining > 0.05 then
```

IsVisible()은 프레임이 화면에 그려지는 순간의 상태를 반환하므로
레이아웃 재계산 / alpha 변경 도중 일시적으로 false가 되어 깜빡임 유발.
