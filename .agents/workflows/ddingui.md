---
description: DDingUI Project — 프로젝트 규칙 및 파일 위치 가이드
---

# DDingUI 프로젝트

## 파일 위치
- 애드온 경로: G:/wow2/World of Warcraft/_retail_/Interface/AddOns/
  - DDingUI_CDM (=DDingUI 폴더)
  - DDingUI_UF
  - DDingUI_Toolkit
  - DDingUI_Profile
  - DDingUI_StyleLib (공유 라이브러리)
  - DDingUI_Essential
  - DDingUI_NamePlate
  - DDingUI_Control
  - DDingUI_Skin_Classic

## 핵심 규칙
1. **코드 치기 전에 생각하기** — 변경의 영향 범위를 먼저 파악
2. **건드리는 건 최소한으로** — 관련 없는 코드는 절대 건드리지 않기
3. **목표를 명확히 하라** — 무엇을 고치는지 정확히 정의 후 작업
4. **단순하게 가라** — 복잡한 추상화보다 직관적인 구현 선호
5. **DB 구조 변경 금지** — SavedVariables 스키마/키/구조 절대 변경 불가
6. **모든 UI 색상은 StyleLib.Colors 참조** — 하드코딩 색상 금지
7. **변경 주석 태그**: `-- [REFACTOR]`, `-- [STYLE]`, `-- [12.0.1]`, `-- [FIX]`
8. **삭제 파일은 _backup/ 복사** — 파일 삭제 전 반드시 백업

## WoW Lua 코딩 규칙
- **Secret Value 안전**: 전투 중 값은 `issecretvalue` 체크 필수
- **SetValue/SetMinMaxValues**: StatusBar API는 secret number를 C++에서 처리 → 안전
- **SetAlphaFromBoolean**: secret boolean은 Lua `if` 비교 불가 → C++ API 사용
- **pcall 보호**: `GetDamageAbsorbs()`, `GetIncomingHeals()` 등 Calculator 메서드는 pcall 필수
- **Taint 방지**: 전투 중 `SetSize()`, `SetPoint()` 등 secure 프레임 변경 금지

## 애드온별 악센트
- StyleLib 참고: `DDingUI_StyleLib.GetAccent("모듈명")`

## 공통 의존성
- StyleLib는 각 애드온의 Libs/DDingUI_StyleLib/에 임베드
- sync_stylelib.bat으로 일괄 배포
- DDingUI_UF는 oUF 제거됨 (standalone mode) — `Units/Standalone/` 모듈 사용