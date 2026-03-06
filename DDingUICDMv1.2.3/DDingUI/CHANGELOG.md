# DDingUI Changelog

---

## v1.2.1

### 버그 수정 / Bug Fixes
- 12.0.1 API 대응: CastingBarFrame forbidden table 크래시 수정 (SetUnit pcall 래핑)
- 12.0.1 API fix: Fixed CastingBarFrame forbidden table crash (SetUnit pcall wrapping)

---

## v1.2.0

### 디자인 변경 / Design Changes
- 설정 패널 전체 디자인 개선
- Improved overall settings panel design
- 타이틀 텍스트에 그라디언트 효과 적용
- Applied gradient effect to title text
- 테두리, 배경, 체크박스, 섹션 구분선, 메뉴 선택 표시 등 시각 요소 개선
- Improved visual elements: borders, backgrounds, checkboxes, section dividers, menu selection

### 기능 추가 / New Features
- 설정 검색: 검색창에 키워드 입력 시 모든 설정 항목을 검색하여 경로와 함께 표시 (예: "쿨다운 매니저 > 일반")
- Settings search: Type keywords to find any setting across all categories, displayed with its path (e.g., "Cooldown Manager > General")
- 검색 결과에서 경로를 클릭하면 해당 설정 페이지로 바로 이동
- Click the path in search results to jump directly to that settings page
- 동적 아이콘 여러 개를 선택한 뒤 한번에 삭제하는 기능 추가
- Added bulk delete for multiple selected dynamic icons

### 버그 수정 / Bug Fixes
- 동적 아이콘 그룹 삭제 시 그룹 안의 아이콘들이 남아있던 문제 수정
- Fixed icons remaining after deleting a dynamic icon group

---

## v1.1.9

### 기능 추가 / New Features
- 버프 추적기: 커스텀 사운드 기능 추가 (버프 활성화/만료 시 사운드 재생)
- Buff Tracker: Added custom sound feature (play sound on buff activation/expiration)
- 쿨다운 매니저: 그룹별 오프셋 기능 추가 (파티/레이드 인원에 따른 위치 조정)
- Cooldown Manager: Added per-group offset feature (position adjustment based on party/raid size)

### 버그 수정 / Bug Fixes
- 버프 추적기: 특정 직업에서 강화효과가 표시되지 않던 문제 수정 (stale auraInstanceID 처리)
- Buff Tracker: Fixed buffs not showing for certain classes (stale auraInstanceID handling)
- 버프 추적기: 비스택 버프가 숨겨지던 문제 수정 (applications 기본값 0 → 1)
- Buff Tracker: Fixed non-stacking buffs being hidden (applications default 0 → 1)
- 버프 추적기: 전투 중 GetBuffStacks secret value 크래시 수정 (pcall 래핑)
- Buff Tracker: Fixed GetBuffStacks secret value crash during combat (pcall wrapping)
- 쿨다운 매니저 강화효과 아이콘에 검은 빈 테두리가 남아있던 문제 수정 (placeholder 프레임 보더 정리)
- Fixed black empty borders persisting on CDM buff icons (placeholder frame border cleanup)
- 전투 중 아이콘 커스터마이징 커스텀 글로우가 비정상적으로 깜빡이던 문제 수정 (글로우 상태 캐싱 추가)
- Fixed icon customization custom glow flickering abnormally during combat (added glow state caching)
- 버프 추적기: 지속시간 텍스트 소수점 자릿수 설정이 전투 중 적용되지 않던 문제 수정 (SetFormattedText 사용)
- Buff Tracker: Fixed duration text decimal places setting not applying during combat (using SetFormattedText)
- 드루이드 폼 변경 시 이전 폼의 자원바 테두리가 남아있던 문제 수정 (폼 변경 시 grace period 비활성화)
- Fixed previous form's resource bar border persisting after druid form change (disable grace period during form changes)
- 전투 중 hideWhenMana 설정이 작동하지 않던 문제 수정 (불필요한 InCombatLockdown 체크 제거)
- Fixed hideWhenMana setting not working during combat (removed unnecessary InCombatLockdown check)
- 쿨다운 매니저: 핵심능력/보조능력 뷰어 간 스와이프 텍스쳐가 다르게 표시되던 문제 수정 (모든 뷰어에 정사각형 텍스쳐 통일 적용)
- Cooldown Manager: Fixed inconsistent swipe texture between Essential/Utility viewers (unified square texture across all viewers)
- 쿨다운 매니저: 아이콘 정렬 순서가 뒤죽박죽이던 문제 수정 (v1.1.7.1 정렬 로직 복원, layoutIndex→GetID→creationOrder fallback chain)
- Cooldown Manager: Fixed scrambled icon sort order (restored v1.1.7.1 sort logic with layoutIndex→GetID→creationOrder fallback chain)
- 편집모드에서 넛지(Nudge) 프레임이 작동하지 않던 문제 수정 (편집모드 중 DDingUI 레이아웃 건너뛰기 복원)
- Fixed EditMode nudge frame not working (restored EditMode layout skip guard)
- 편집모드에서 "요소에 맞춰 정렬"(Snap) 기능이 DDingUI 활성화 시 정상 작동하지 않던 문제 수정 (뷰어 프레임 크기를 CDM/LEMO 관리에 맡기도록 변경)
- Fixed EditMode "Snap to Elements" not working properly with DDingUI enabled (stopped overriding viewer frame size, let CDM/LEMO manage it)

---

## v1.1.8.1

### 변경 사항 / Changes
- "버프 바" 이름을 "추적중인 막대"로 변경 (버프 추적기와의 혼동 방지)
- Renamed "Buff Bar" to "Tracked Bars" to avoid confusion with Buff Tracker
- 전문화별 프로필 설정을 별도 탭에서 프로필 관리 탭 내 체크박스로 이동
- Moved per-spec profile toggle into Profile Management tab
- 추적중인 막대 지속시간 모드 구분선에 두께 옵션 추가
- Added tick width option for duration mode dividers in Tracked Bars

---

## v1.1.8

### 기능 추가 / New Features
- 비행 시 숨기기 옵션이 이제 쿨다운 매니저 아이콘까지 포함하여 모든 DDingUI 요소를 부드럽게 숨김
- Flight Hide option now smoothly hides all DDingUI elements including Cooldown Manager icons
ㅁ
### 버그 수정 / Bug Fixes
- 글로우/강조 설정 변경 시 설정창이 깜빡이며 스크롤 위치가 초기화되던 문제 수정
- Fixed settings panel flickering and scroll position resetting when changing glow/highlight settings
- 폰트 선택 드롭다운에서 일부 설치된 폰트가 표시되지 않던 문제 수정
- Fixed some installed fonts not appearing in font selection dropdowns
- 버프 바(BuffBarCooldownViewer) 위치 핑퐁 현상 수정 (바가 활성화/비활성화 시 위아래로 왔다갔다하던 문제)
- Fixed Buff Bar position ping-pong issue (bars jumping up/down on activate/deactivate)
- 포인트별 색상(Per-Point Color) 설정 오류 수정
- Fixed Per-Point Color settings error
- 아이콘 커스터마이징 고스트 글로우 수정
- Fixed Icon Customization ghost glow issue
- SpecProfiles 이벤트 핸들러 수정 (PLAYER_SPECIALIZATION_CHANGED unit 인자 문제)
- Fixed SpecProfiles event handler (PLAYER_SPECIALIZATION_CHANGED unit arg issue)
- SetStatusBarColor 크래시 수정
- Fixed SetStatusBarColor crash
- 문자열 비교 에러 수정
- Fixed string comparison error

### 변경 사항 / Changes
- 클래스 버프 알림 모듈 비활성화 및 UI에서 숨김
- Disabled Class Buff Missing Alert module and hidden from UI

---

## v1.1.7.2

### 기능 추가 / New Features
- 보조 강조 효과 추가 (전투 보조 시스템의 다음 추천 스킬 하이라이트)
- Added Assist Highlight (next suggested spell highlight from Assisted Combat)
- 보조 강조 유형 선택: 플립북(블리자드 기본) / LibCustomGlow
- Assist Highlight type selection: Flipbook (Blizzard default) / LibCustomGlow
- 뷰어별 개별 보조 강조 설정 (활성화, 유형, 색상, 크기 등)
- Per-viewer Assist Highlight settings (enable, type, color, scale, etc.)

### 버그 수정 / Bug Fixes
- 프록 글로우 설정 경로 불일치 수정 (뷰어별 설정이 적용되지 않던 문제)
- Fixed proc glow settings path mismatch (per-viewer settings not applied)
- 프록/보조 강조 글로우 유형 변경 시 세부 옵션이 즉시 표시되지 않던 문제 수정
- Fixed sub-options not updating immediately when changing glow/highlight type
- GUI SoftRefresh API 추가 (커스텀 GUI 외부 새로고침 지원)
- Added GUI SoftRefresh API for external config refresh support

---

## v1.1.7.1

### 기능 추가 / New Features
- 버프 추적기 개별 비활성화 기능 추가 (트래커별 활성화/비활성화 토글)
- Added per-buff enable/disable toggle for Buff Tracker
- 주 자원 바: 마나일 때 자동 숨기기 옵션 추가
- Primary Resource Bar: Added option to hide bar when resource is Mana
- 보조 자원 바: 세부 색상 설정 추가 (차지드 포인트, 최대치, 재충전, 포인트별, 세그먼트별 색상)
- Secondary Resource Bar: Added detailed color options (charged point, max resource, recharge, per-point, per-segment colors)
- 보조 자원 바: DK 룬 전문화별 색상 지원 (혈기/냉기/부정)
- Secondary Resource Bar: Added DK rune spec-specific colors (Blood/Frost/Unholy)
- 펫 알림: 테두리 크기/색상 설정 추가
- Pet Alert: Added border size/color options
- 펫 알림: 인스턴스 전용 표시 옵션 추가
- Pet Alert: Added instance-only display option
- 색상 설정: 각 색상 피커에 초기화 버튼 추가
- Color Settings: Added reset button for each color picker

### 버그 수정 / Bug Fixes
- 비전투 중 생존기/쿨기 글로우 오류 수정 (secret value 비교 에러)
- Fixed personal cooldown glow error outside combat (secret value comparison)
- 포식 악마사냥꾼 보조자원(소울 파편) 메타모포시스 후 값 고정 수정 (secret value 처리)
- Fixed Feast DH secondary resource (Soul Fragments) stuck after Metamorphosis (secret value handling)
- GUI 설정창 스크롤 시 secret value 에러 수정
- Fixed GUI settings scroll secret value error
- 룬 타이머 색상 오류 수정
- Fixed rune timer color error
- 색상 피커 hasAlpha 관련 오류 수정
- Fixed color picker hasAlpha error
- Grace Period 3초 → 5초로 증가 (전문화 변경 시 바 깜빡임 방지)
- Increased Grace Period from 3s to 5s (prevents bar flicker on spec change)

---

## v1.1.6.7

### 버그 수정 / Bug Fixes
- 부정 죽기 펫 미싱 알림 미표시 수정 (IsPlayerSpell fallback 추가)
- Fixed Pet Missing alert not showing for Unholy DK (added IsPlayerSpell fallback)
- 쐐기/레이드에서 미싱버프 오탐 수정 (spellId + name 듀얼 매칭, C_Spell.IsSpellInRange 범위 체크)
- Fixed Missing Buff false positives in M+/Raid (dual matching spellId + name, C_Spell.IsSpellInRange range check)
- 팔라딘 헌신의 오라 그룹 체크 → 자기 자신 체크로 수정
- Fixed Paladin Devotion Aura from group check to self-only check

### 기능 개선 / Improvements
- 버프 트래커 전문화별 설정을 계정 공유로 변경 (db.profile → db.global)
- Changed BuffTracker per-spec settings to account-wide sharing (db.profile → db.global)
- 같은 전문화 캐릭터 간 trackedBuffsPerSpec 설정 자동 공유
- Auto-share trackedBuffsPerSpec settings across characters with same specialization
- 기존 캐릭터별 설정 자동 마이그레이션 지원
- Automatic migration from per-character to account-wide storage

---

## v1.1.6.6

### 성능 최적화 / Performance Optimizations
- UNIT_AURA 이벤트를 RegisterUnitEvent로 변환하여 레이드에서 ~95% 이벤트 감소 (5개 파일)
- Converted UNIT_AURA events to RegisterUnitEvent for ~95% event reduction in raids (5 files)
- FocusCastBar/TargetCastBar의 UNIT_SPELLCAST 이벤트를 유닛별 필터링으로 변환
- Converted UNIT_SPELLCAST events in FocusCastBar/TargetCastBar to unit-specific filtering
- ResourceBars의 UNIT_POWER 이벤트를 플레이어 전용으로 변환
- Converted UNIT_POWER events in ResourceBars to player-only
- BuffTrackerBar 존 변경 시 타이머 5개 → 2개로 축소 + 디바운스 적용
- Reduced BuffTrackerBar zone change timers from 5 to 2 with debounce

### 버그 수정 / Bug Fixes
- 동적 아이콘 설정이 전문화 변경 시 리셋되는 문제 수정 (SpecProfiles 자동 저장 트리거 추가)
- Fixed dynamic icon settings resetting on spec change (added SpecProfiles auto-save trigger)
- 프로필 변경 시 이전 프로필의 동적 아이콘이 남아있는 문제 수정
- Fixed previous profile's dynamic icons persisting after profile switch
- ElvUI/Masque 스킨 충돌 감지가 실제 스킨 미적용 상태에서도 메시지를 표시하던 문제 수정
- Fixed ElvUI/Masque skin conflict detection showing message even when skins weren't applied
- Pet Missing 알림이 비행/탈것/수영/차량 중에도 표시되던 문제 수정
- Fixed Pet Missing alert showing while flying/mounted/swimming/in vehicle

---

## v1.1.6.4

### 버그 수정 / Bug Fixes
- 이동 모드에서 버프 추적기 위치가 저장/로드 시 점점 멀어지는 버그 수정 (스케일 계산 오류)
- Fixed buff tracker positions drifting further away on each save/load cycle in mover mode (scale calculation error)

### 새 기능 / New Features
- 버프 추적기 개별 프레임 계층(Frame Strata) 설정 추가 — 각 추적 항목마다 독립적으로 그리기 계층 조절 가능
- Added per-buff Frame Strata setting for Buff Tracker — each tracked buff can now have its own drawing layer override

---

## v1.1.5

### 주요 기능 요약

**DDingUI**는 블리자드 쿨다운 매니저(CDM)와 연동되는 리소스 바 및 UI 커스터마이징 애드온입니다.

---

### 🎯 핵심 기능

#### 자원 바 (Resource Bars)
- **주 자원 바**: 마나, 분노, 기력 등 주요 자원 표시
- **보조 자원 바**: 콤보 포인트, 룬, 소울 샤드 등 보조 자원 표시
- **버프 트래커 바**: CDM 연동으로 버프/디버프 스택 및 지속시간 추적
  - 지속시간 자동 감지 (기본 ON): 버프 활성화 시 CDM에서 실시간으로 duration 읽기
  - 최대 중첩 직접 입력 (1~9999)
  - 바/원형/사각형/도넛 스타일 지원

#### 시전 바 (Cast Bars)
- 플레이어/대상/주시대상/보스 시전 바
- 시전 중단 시 색상 변경 및 페이드 효과
- 강화 주문(Empowered) 단계별 색상 지원

#### 아이콘 커스터마이징
- **글로우 효과**: 쿨다운 준비 완료 또는 버프 활성화 시
- **스와이프 색상**: 아이콘별 쿨다운 스와이프 커스텀
- **아우라 오버레이**: 버프 지속시간 표시

#### 커스텀 아이콘
- 소비용품, 장신구, 방어기, 종족 스킬 아이콘
- 동적 아이콘 그룹 관리

---

### 🛠️ UI/UX

- **이동 모드** (`/ddmove`): ElvUI 스타일 프레임 위치 조절
  - 드래그 이동, 스냅 정렬, 미세 조정
  - 앵커 포인트 변경, 위치 자동 저장
- **GUI 스케일**: 설정창 크기 조절 (50%~150%)
- **모던 플랫 디자인**: 깔끔한 설정창 UI

---

### 📋 명령어

| 명령어 | 설명 |
|--------|------|
| `/dui` | 설정창 열기 |
| `/ddmove` | 이동 모드 토글 |
| `/btscan` | 추적 가능한 버프 목록 확인 |
| `/ddingcdm cache` | CDM 캐시 통계 확인 |

---

### 🔧 기술적 특징

- **Taint-Free**: 전투 중 Blizzard UI 오염 방지
- **Secret Value 처리**: WoW 12.0+ issecretvalue API 대응
- **CDM 연동**: layoutIndex 기반 안정적인 프레임 추적
- **TaintLess 라이브러리**: 블리자드 UI taint 자동 완화

---

## Version History

### v1.1.6
- 일반 - Missing Buff Alert 항목 추가 (직업별 버프 알림)
- 버프 바 - 다이나믹 디렉션 옵션 추가 (위/아래 방향 선택)
- 버프 추적기 - 세로바/링 모양 추가
- 버프 추적기 - 수동 트래킹 트리거 스킬 인식 버그 수정
- 설정창 스크롤 버그 수정

### v1.1.5
- GUI 스케일 조절 기능
- 버프 활성화 글로우 효과
- 글로우 발동 조건 설정 (쿨다운/버프)
- 버프 트래커 지속시간 자동 감지
- 최대 중첩 입력 필드 변경
- 설정창 모던 디자인 적용
- 한글화 완료

### v1.1.4.3
- Taint 안정성 대폭 개선
- 전투 중 아우라 글로우 수정
- 설정 패널 스크롤 수정

### v1.1.4
- cooldownID → layoutIndex 기반 감지 변경
- Secret Value 에러 수정

### v1.1.3
- 이동 모드 (Mover Mode) 추가
- 전투 중 Taint 에러 수정

### v1.1.2
- 소수점 입력 지원
- 프레임 선택 버튼
- 시전 중단 효과
- 아이템 폴백 기능

### v1.1.1
- 최초 릴리즈

---
---

# DDingUI Changelog (English)

---

## v1.1.5

### Overview

**DDingUI** is a resource bar and UI customization addon that integrates with Blizzard's Cooldown Manager (CDM).

---

### 🎯 Core Features

#### Resource Bars
- **Primary Resource Bar**: Mana, Rage, Energy, etc.
- **Secondary Resource Bar**: Combo Points, Runes, Soul Shards, etc.
- **Buff Tracker Bar**: Track buff/debuff stacks and duration via CDM
  - Auto-detect duration (default ON): Reads duration from CDM in real-time
  - Manual max stacks input (1~9999)
  - Bar/Circular/Square/Donut styles

#### Cast Bars
- Player/Target/Focus/Boss cast bars
- Interrupted cast color change with fade effect
- Empowered spell stage colors

#### Icon Customization
- **Glow Effects**: On cooldown ready or buff active
- **Swipe Color**: Per-icon cooldown swipe customization
- **Aura Overlay**: Buff duration display

#### Custom Icons
- Consumables, Trinkets, Defensives, Racial abilities
- Dynamic icon group management

---

### 🛠️ UI/UX

- **Mover Mode** (`/ddmove`): ElvUI-style frame positioning
  - Drag to move, snap alignment, fine adjustment
  - Anchor point changes, auto-save positions
- **GUI Scale**: Settings window scale (50%~150%)
- **Modern Flat Design**: Clean settings UI

---

### 📋 Commands

| Command | Description |
|---------|-------------|
| `/dui` | Open settings |
| `/ddmove` | Toggle mover mode |
| `/btscan` | List trackable buffs |
| `/ddingcdm cache` | View CDM cache stats |

---

### 🔧 Technical Features

- **Taint-Free**: No Blizzard UI contamination during combat
- **Secret Value Handling**: WoW 12.0+ issecretvalue API support
- **CDM Integration**: Stable frame tracking via layoutIndex
- **TaintLess Library**: Automatic Blizzard UI taint mitigation

---

## Version History

### v1.1.6
- General - Added Missing Buff Alert (class-specific buff reminders)
- Buff Bar - Added dynamic direction option (grow up/down)
- Buff Tracker - Added vertical bar and ring display modes
- Buff Tracker - Fixed manual tracking trigger spell recognition bug
- Fixed settings panel scroll bug

### v1.1.5
- GUI scale control
- Buff active glow effects
- Glow trigger settings (cooldown/buff)
- Buff tracker auto-detect duration
- Max stacks input field
- Modern settings design
- Full Korean localization

### v1.1.4.3
- Major taint stability improvements
- Combat aura glow fix
- Settings panel scroll fix

### v1.1.4
- cooldownID → layoutIndex detection
- Secret Value error fix

### v1.1.3
- Mover Mode added
- Combat taint error fix

### v1.1.2
- Decimal input support
- Frame picker button
- Interrupted cast effect
- Item fallback feature

### v1.1.1
- Initial release
ㅇ