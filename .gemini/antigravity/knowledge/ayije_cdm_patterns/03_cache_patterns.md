# Pattern 03: 캐시 우선 조회 (spellIDCache, styleCacheVersion)

## 핵심 아이디어
API 호출 비용이 높은 연산(SpellID 조회, 스타일 계산)은 최초 1회만 수행하고
버전 번호 또는 weak-table 키로 캐시. 캐시 히트 시 API 완전 생략.

## 소스 위치
- `Ayije_CDM_/Core/Init.lua` (spellIDCache)
- `Ayije_CDM_/Core/Constants.lua` (styleCacheVersion, _DesaturationCurve)

## 코드 패턴

### spellIDCache — frame 기반 weak-table 캐시

```lua
-- Init.lua:
local spellIDCache = setmetatable({}, { __mode = "k" })  -- frames가 GC되면 자동 정리

local function GetCachedBaseSpellID(CDM, frame)
    local cached = spellIDCache[frame]
    if cached ~= nil then return cached end          -- 캐시 히트: API 호출 0

    -- 캐시 미스: 안전하게 계산
    local spellID
    pcall(function()
        spellID = frame:GetAuraSpellID() or frame:GetSpellID()
    end)
    if spellID and spellID > 0 then
        local ok, base = pcall(C_SpellBook.FindBaseSpellByID, spellID)
        spellID = (ok and base) or spellID
    end

    spellIDCache[frame] = spellID or false           -- false = "조회했으나 없음" (재조회 방지)
    return spellIDCache[frame]
end
```

### styleCacheVersion — 버전 번호 기반 무효화

```lua
-- Main.lua RegisterRefreshCallback:
CDM:RegisterRefreshCallback("styleCache", function()
    CDM.styleCacheVersion = (CDM.styleCacheVersion or 0) + 1
    RefreshStyleCache()   -- 버전 증가 → 다음 조회 시 재계산
end, 10)

-- 사용 측:
local function GetIconStyle(frame)
    local cached = iconStyleCache[frame]
    if cached and cached.version == CDM.styleCacheVersion then
        return cached.style                          -- 버전 일치: 캐시 반환
    end
    -- 버전 불일치: 재계산 후 캐시 갱신
    local style = ComputeStyle(frame)
    iconStyleCache[frame] = { style = style, version = CDM.styleCacheVersion }
    return style
end
```

### _DesaturationCurve — 커브 기반 상태 평가 (IsVisible 대체)

```lua
-- Constants.lua:
-- IsVisible() 은 레이아웃 업데이트 중 불안정 → C_CurveUtil로 대체
_DesaturationCurve = C_CurveUtil.CreateCurve({
    { x = 0.0, y = 1.0 },   -- 쿨다운 없음 → desaturate
    { x = 0.1, y = 0.0 },   -- 쿨다운 시작 → 컬러
})

_GCDFilterCurve = C_CurveUtil.CreateCurve({
    { x = 0.0, y = 1.0 },
    { x = 1.5, y = 1.0 },   -- GCD 길이 이하 → 필터
    { x = 1.51, y = 0.0 },
})

-- 사용: frame:EvaluateRemainingDuration() 결과를 커브에 통과
local remaining = frame:EvaluateRemainingDuration()
local shouldDesaturate = _DesaturationCurve:Evaluate(remaining) > 0.5
```

## DDingUI 적용 포인트

### FrameController.GetSpellName 최적화 (P1)

현재: 매 Reconcile 틱마다 `iconSpellNameMap` 체크 없이 `GetSpellName()` 호출.

```lua
-- 현재 (FrameController.lua L718):
local name = self:GetSpellName(icon)   -- pcall×2 + API×2 매 틱 실행

-- 개선 (Ayije spellIDCache 패턴):
local name = iconSpellNameMap[icon.cooldownID]
if not name then
    name = self:GetSpellName(icon)
    if name then
        iconSpellNameMap[icon.cooldownID] = name
    end
end
-- → 캐시 히트 시 pcall/API 완전 생략
```

### ScanCDMViewers suppressed 체크 최적화 (P2 캐시화)

```lua
-- 개선: suppressed set 변경 시에만 재계산
local suppressedCacheVersion = 0
local suppressedCacheSet = {}

local function GetSuppressedSet()
    local bridge = DDingUI.DynamicIconBridge
    if bridge and bridge._suppressedVersion ~= suppressedCacheVersion then
        suppressedCacheVersion = bridge._suppressedVersion
        wipe(suppressedCacheSet)
        for id in pairs(bridge:GetSuppressedSpellIDs()) do
            suppressedCacheSet[id] = true
        end
    end
    return suppressedCacheSet
end
-- → 스펠 할당 변경 시에만 재계산, 전투 중 매 틱 pcall 제거
```

## weak-table 패턴 정리

```lua
-- frame이 GC되면 자동 정리 (메모리 누수 없음)
local cache = setmetatable({}, { __mode = "k" })

-- false 저장 관례: "조회했으나 값 없음"을 nil과 구분
-- nil → 아직 조회 안 함 (조회 시도 필요)
-- false → 조회했으나 없음 (재조회 불필요)
-- value → 유효한 캐시
```
