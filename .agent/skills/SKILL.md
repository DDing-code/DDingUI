---
name: DDingUI Frontend Guide
description: DDingUI WoW UI 프론트엔드 개발 — Ellesmere UI 기법 + 자주 하는 실수 방지
---

# DDingUI Frontend Guide
> Ellesmere UI 역공학 분석 + 실전 실수 패턴 모음

---

## 1. 레이아웃 — cursorY 흐름 패턴

### ✅ 올바른 방법: 단일 cursorY
```lua
local cursorY = -10
local PAD = 6
local SECTION_PAD = 12

-- 타이틀
title:SetPoint("TOP", panel, "TOP", 0, cursorY)
cursorY = cursorY - 16

-- 다음 요소
nextElement:SetPoint("TOP", panel, "TOP", 0, cursorY)
cursorY = cursorY - nextElement_HEIGHT - PAD
```

### ❌ 하면 안 되는 것
```lua
-- 실수 1: 절대 Y와 상대 앵커 혼용
title:SetPoint("TOP", panel, "TOP", 0, -10)
grid:SetPoint("TOP", title, "BOTTOM", 0, -8)  -- 체인
xLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -310)  -- 갑자기 절대!
-- → 요소 추가/삭제 시 아래 요소가 겹침

-- 실수 2: 생성 시 임시 위치 → ClearAllPoints → 재배치
btn = CreateBtn(...)  -- 임시 위치로 생성
btn:ClearAllPoints()  -- 나중에 다시
btn:SetPoint(...)     -- 실제 위치
-- → 코드 가독성 저하, 실수 유발

-- 실수 3: 생성 순서와 배치 순서 불일치
-- dropdown을 먼저 생성하지만, 실제 SetPoint는 200줄 뒤에
-- → 중간에 참조할 앵커가 nil이 되는 버그 발생
```

### 규칙
1. **한 패널 안에서 TOP 앵커는 항상 panel, "TOP" 기준 cursorY만 사용**
2. **수평 배치만 다른 요소 기준** (예: `LEFT`, `RIGHT`)
3. **CreateXxx 함수 내부에서 cursorY를 직접 감소시키기** (클로저 활용)
4. **요소 생성 순서 = 화면 배치 순서** (위→아래)

---

## 2. Ellesmere UI 핵심 기법

### 2.1 Pixel Perfect 보더 (MakeBorder)
WoW의 `BackdropTemplate` 보더는 스케일에 따라 흐릿해짐.
**해결:** 4개 텍스처로 물리 1px 보더 구현.

```lua
-- Ellesmere 패턴
local PP = {}
PP.physicalWidth, PP.physicalHeight = GetPhysicalScreenSize()
PP.perfect = 768 / PP.physicalHeight
PP.mult = PP.perfect / (UIParent:GetScale() or 1)

function PP.Scale(x)
    if x == 0 then return 0 end
    local m = PP.mult
    if m == 1 then return x end
    local y = m > 1 and m or -m
    return x - x % (x < 0 and y or -y)
end

-- 필수: SetColorTexture 후 반드시 호출
function PP.DisablePixelSnap(obj)
    if obj.SetSnapToPixelGrid then
        obj:SetSnapToPixelGrid(false)
        obj:SetTexelSnappingBias(0)
    end
end
```

### 2.2 Design Token 시스템
하드코딩 색상값을 중앙 관리. DDingUI에서는 `SL.Colors` 테이블이 이 역할.

```lua
-- ❌ 하드코딩
btn:SetBackdropColor(0.15, 0.15, 0.15, 0.8)

-- ✅ 토큰 참조
local bg = SL.Colors.bg.hover
btn:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
```

### 2.3 RegisterWidgetRefresh — 프레임 재생성 없이 값만 갱신
```lua
local _refreshList = {}
function RegisterRefresh(fn)
    _refreshList[#_refreshList + 1] = fn
end

-- 설정 변경 시: 프레임 파괴 X, 값만 업데이트
function RefreshAll()
    for _, fn in ipairs(_refreshList) do fn() end
end
```

### 2.4 MakeStyledButton — 24색 배열
```lua
-- colours[1-4]:  bg normal
-- colours[5-8]:  bg hover
-- colours[9-12]: border normal
-- colours[13-16]: border hover
-- colours[17-20]: text normal
-- colours[21-24]: text hover
-- → OnEnter/OnLeave에서 인덱스만 바꿈. 코드 중복 제거.
```

### 2.5 Taint-Free 애니메이션
보호된 프레임에서 `CreateAnimationGroup` → Taint!
```lua
-- ✅ OnUpdate + 수학
frame:SetScript("OnUpdate", function(self, elapsed)
    timer = timer + elapsed
    local alpha = 0.25 + 0.25 * (0.5 + 0.5 * math.sin(timer))
    self:SetAlpha(alpha)
end)

-- 30fps 제한으로 성능 확보
accum = accum + elapsed
if accum < 0.033 then return end
accum = 0
```

---

## 3. 자주 하는 실수 TOP 10

### 실수 1: Named 프레임 재생성 불가
```lua
-- ❌ /reload 후에도 `if self.NudgeFrame then return end`로 스킵됨
-- WoW는 Named 프레임을 리로드 시 파괴하지 않음
-- → 레이아웃 변경 후 반드시 게임 완전 종료 + 재시작
```

### 실수 2: nil 참조 — 생성 순서 의존
```lua
-- ❌ downBtn이 아직 생성 안 됐는데 참조
dropdown:SetPoint("TOP", nudge.downBtn, "BOTTOM", 0, -12)
-- nudge.downBtn = nil → 에러!

-- ✅ 임시 위치로 생성 후 ClearAllPoints 재배치
-- 또는 cursorY 패턴으로 생성 순서 = 배치 순서 통일
```

### 실수 3: anchorTo가 nil — 조건부 프레임 참조
```lua
-- ❌ 특정 조건에서만 생성되는 프레임을 앵커로 사용
container:SetPoint("TOPLEFT", optionalFrame, "BOTTOMLEFT", 0, -4)
-- optionalFrame이 nil이면 에러

-- ✅ 항상 존재하는 앵커 사용 (panel 자체 + cursorY)
container:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, cursorY)
```

### 실수 4: ClearAllPoints 누락
```lua
-- ❌ SetPoint 2번 → 두 앵커가 동시에 적용 → 의도치 않은 크기 변형
frame:SetPoint("TOP", a, "BOTTOM", 0, 0)
frame:SetPoint("TOP", b, "BOTTOM", 0, -20)  -- 위의 것이 남아있음!

-- ✅ 재배치 전 반드시 ClearAllPoints
frame:ClearAllPoints()
frame:SetPoint("TOP", b, "BOTTOM", 0, -20)
```

### 실수 5: 패널 너비 초과
```lua
-- 패널 240px인데 요소가 260px
-- 슬라이더 X=140 + Width=120 = 260 → 오른쪽으로 삐져나옴
-- ✅ 항상 계산: elementX + elementWidth <= panelWidth - padding
```

### 실수 6: pB 변수 섀도잉
```lua
local pB = panelBorder  -- 외부
local function CreateSomething()
    local pB = {0.25, 0.25, 0.25, 0.5}  -- 내부에서 다시 선언
    -- → 외부 pB가 가려져서 다른 곳에서 사용 시 의도와 달라짐
end
```

### 실수 7: 드롭다운 메뉴 strata/level
```lua
-- 드롭다운 펼침 목록이 다른 요소 아래로 묻힘
-- ✅ 메뉴 프레임에 높은 strata 명시
menu:SetFrameStrata("TOOLTIP")
```

### 실수 8: slider fill 업데이트 타이밍
```lua
-- 생성 직후 slider:GetValue()로 fill 너비 계산 → track Width가 0
-- ✅ C_Timer.After(0, UpdateFill) 로 다음 프레임에서 계산
```

### 실수 9: SetSize vs SetPoint 2개의 충돌
```lua
-- ❌ SetSize(200, 50) + SetPoint("RIGHT", panel, "RIGHT", -10, 0)
-- → 너비가 200으로 고정되어 LEFT 앵커가 무시됨

-- 너비를 양쪽 앵커로 결정하려면 SetSize 대신:
frame:SetHeight(50)  -- 높이만 고정
frame:SetPoint("LEFT", panel, "LEFT", 10, 0)
frame:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
```

### 실수 10: unpack(table) 색상 적용 후 수정
```lua
-- ❌ 테이블 참조가 공유됨
local color = SL.Colors.bg.main
color[4] = 0.5  -- → 원본 SL.Colors.bg.main도 변경됨!

-- ✅ 복사 후 수정
local color = {unpack(SL.Colors.bg.main)}
color[4] = 0.5
```

---

## 4. DDingUI 위젯 팩토리 API

### CreateFlatDropdown
```lua
CreateFlatDropdown(parent, labelText, width,
    anchorPoint, anchorTo, anchorRelPoint, xOff, yOff,
    items,      -- { {text="표시명", value="값"}, ... }
    onChange)   -- function(selectedValue)
-- 반환: container (container.button, container.label, container:SetValue, container:SetItems)
```

### CreateFlatSlider
```lua
CreateFlatSlider(parent, labelText, minV, maxV, stepV, defaultV,
    anchorTo, xOff, yOff,
    onChange)  -- function(value)
-- 반환: container (container.slider, container.label)
```

### CreateCheckbox (내부 함수, cursorY 자동 감소)
```lua
CreateCheckbox(label, settingKey, onClick, indent)
-- cursorY를 자동으로 -20 감소시킴
-- 반환: container (:SetChecked, :GetChecked)
```

---

## 5. CDM vs UF 넛지 패널 차이점

| 항목 | CDM | UF |
|------|-----|-----|
| 악센트 컬러 | 오렌지 `{0.90, 0.45, 0.12}` | 블루 `{0.23, 0.65, 0.89}` |
| GetAccent 호출 | `SL.GetAccent("CDM")` | `SL.GetAccent("UF")` |
| 모듈 매핑 | `MoverToModuleMapping` | UF 자체 앵커 시스템 |
| 파일 위치 | `DDingUI/Core/Movers.lua` | `DDingUI_UF/Core/EditMode.lua` |

**디자인은 완전 동일, 악센트 컬러만 다르게** 유지.

---

## 6. 체크리스트 — 패널 작업 전 확인

- [ ] cursorY 흐름으로 모든 요소 배치하고 있는가?
- [ ] 요소 생성 순서 = 화면 배치 순서(위→아래)인가?
- [ ] 모든 요소의 총 너비가 패널 너비 이내인가?
- [ ] ClearAllPoints 없이 SetPoint를 중복 호출하지 않았는가?
- [ ] 하드코딩 색상 대신 SL.Colors 토큰을 사용했는가?
- [ ] Named 프레임 변경 후 게임 완전 종료/재시작 안내했는가?
- [ ] `end` 균형 확인 (check_ends4.py) 통과하는가?
