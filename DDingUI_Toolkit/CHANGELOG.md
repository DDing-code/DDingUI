# DDingUI Toolkit Changelog

## 2.1.2

Release date: 2026-08-22

## English

### New Modules

- **Premade Group Filter:** Added seasonal dungeon selection, role-slot, tank, healer, and Bloodlust-fit filters, leader rating and best-key requirements, sorting, specialization icons, and leader score display.
- **Stasis Tracker:** Added three stored-spell slots, question-mark empty icons, release-window tracking, and options for size, spacing, fonts, timer, and individual colors.
- **Bloodlust Timer:** Added active and exhaustion tracking with icon, bar, cooldown swipe, time-text format and order, colors, glow, TGA animation, start music, and start, end, and ready sounds.
- **Ready Check Assistant:** Added specialization, talent loadout, and durability checks with threshold, reporting, button, size, anchor, and placement options.
- **Combat Start/End Alert:** Added simple and animated modes with separate start and end text, detailed color palettes, size, position, frame priority, animation, and sound options.

### Option Changes

- Added a dedicated Class Features category with class-colored module titles.
- Added account-wide, one-time new-module notices with direct settings links. New modules remain disabled for existing profiles until enabled manually.
- Added Toolkit profile-code export and import. Saved Notepad contents are excluded from exported codes.
- Added separate self and inspect switches to Item Level, plus melee, ranged, tank, and healer display switches to Character Position Marker.
- Added Notepad list scrolling and updated Party Tracker's Bloodlust exhaustion tracking for WoW 12.1.

### Fixes

- Stabilized Target Spell icon placement, corrected the Bloodlust Timer cooldown swipe, and improved inspection reliability under WoW 12.1 restrictions.

## 한국어

### 신규 모듈

- **파티 검색 필터:** 시즌 던전 선택, 역할 자리, 탱커, 힐러, 블러드 적합 필터와 파티장 점수·최고 단수 조건, 정렬, 전문화 아이콘 및 파티장 점수 표시를 추가했습니다.
- **정지장 트래커:** 저장 주문 3칸, 미저장 칸 물음표 아이콘, 방출 제한시간 추적과 크기, 간격, 글꼴, 타이머 및 개별 색상 옵션을 추가했습니다.
- **블러드 타이머:** 블러드 지속시간과 소진 추적, 아이콘, 막대, 쿨다운 스와이프, 시간 텍스트 형식·순서, 색상, 글로우, TGA 애니메이션, 시작 음악 및 시작·종료·준비 완료 효과음 옵션을 추가했습니다.
- **준비 확인 도우미:** 전문화, 특성 불러오기와 내구도 점검 및 기준값, 파티 알림, 버튼, 크기, 기준 방향과 위치 옵션을 추가했습니다.
- **전투 시작/종료 알림:** 심플·모션 표현과 시작·종료 문구, 세부 색상, 크기, 위치, 표시 우선순위, 애니메이션 및 사운드 옵션을 추가했습니다.

### 옵션 변경

- 직업색 모듈 제목을 사용하는 직업별 특수 기능 분류를 추가했습니다.
- 계정당 한 번 표시되는 신규 모듈 안내와 설정 바로가기를 추가했습니다. 기존 프로필의 신규 모듈은 직접 활성화하기 전까지 꺼진 상태를 유지합니다.
- Toolkit 프로필 코드 내보내기·불러오기를 추가했습니다. 메모장 본문은 내보내기 코드에서 제외됩니다.
- 아이템 레벨에 내 캐릭터·살펴보기 개별 활성 옵션을, 캐릭터 위치 마커에 근딜·원딜·탱커·힐러 개별 표시 옵션을 추가했습니다.
- 메모장 목록 스크롤을 추가하고 Party Tracker의 WoW 12.1 블러드 소진 추적을 갱신했습니다.

### 수정 사항

- 타겟 스펠 아이콘 위치를 안정화하고 블러드 타이머 쿨다운 스와이프 방향과 WoW 12.1 살펴보기 동작을 보정했습니다.

## 2.1

Release date: 2026-08-14

## English

- Updated addon metadata and runtime version reporting for WoW 12.1.
- Refreshed the shared DDingUI branding and corrected the wordmark color treatment.
- Reworked the settings workspace and edit mode with clearer categories, live previews, safer positioning, and explicit module activation for existing profiles.
- Added combat utilities for cast alerts, focus interrupts, combat timing, range display, and player-position marking.
- Added buff reminders, party-fill alerts, death alerts, raid break timing, guarded spirit release, and per-instance raid loot-pass approval.
- Improved combat safety for item-level inspection, resurrection handling, module previews, and right-click camera control.
- Removed the legacy keystone tracker and expanded English and Korean localization coverage across the active modules.

## 한국어

- WoW 12.1에 맞게 애드온 메타데이터와 런타임 버전 표시를 업데이트했습니다.
- DDingUI 공통 브랜딩을 새로 적용하고 워드마크 색상 처리를 보정했습니다.
- 설정 작업공간과 편집 모드를 명확한 분류, 실시간 미리보기, 안전한 위치 조절 방식으로 개편하고 기존 프로필의 신규 모듈은 명시적으로 활성화하도록 변경했습니다.
- 시전 알림, 주시 대상 차단, 전투 시간, 사거리 표시 및 캐릭터 위치 표시 전투 도구를 추가했습니다.
- 강화효과 알림, 파티 모집 완료 알림, 사망 알림, 공격대 휴식 타이머, 영혼 전환 보호 및 인스턴스별 공격대 전리품 자동 포기 승인 기능을 추가했습니다.
- 아이템 레벨 조회, 부활 처리, 모듈 미리보기 및 우클릭 시점 조작의 전투 안전성과 안정성을 개선했습니다.
- 기존 쐐기돌 추적기를 제거하고 현재 사용되는 모듈 전반의 영문·한글 번역 범위를 보완했습니다.

## 1.3.1

Release date: 2026-07-31

## English

- Rebuilt the settings window around a three-column workspace with smoother scrolling, resizing, a dashboard, and multi-profile management.
- Upgraded edit mode with clearer frame selection, live previews, and safer module positioning.
- Expanded combat tools with casting alerts, focus interrupt customization, a combat timer, range display, and a player-position marker.
- Added buff reminders, party recruitment completion alerts, death alerts, raid spirit-release protection, and raid auto-pass tools.
- Improved shared styling, localization, previews, and runtime stability across Toolkit modules.
- Moved custom talent-background assets to a configurable, update-safe folder under `Interface`.

## 한국어

- 설정창을 3열 작업공간으로 재구성하고 부드러운 스크롤, 크기 조절, 대시보드, 다중 프로필 관리를 추가했습니다.
- 편집 모드의 프레임 선택, 실시간 미리보기, 모듈 위치 저장 안정성을 개선했습니다.
- 시전 알림, 주시 대상 차단바 세부 설정, 전투 타이머, 사거리 표시, 캐릭터 위치 마커를 추가·확장했습니다.
- 강화효과 알림, 파티 모집 완료 알림, 사망 알림, 공격대 영혼 전환 보호, 공격대 자동 포기 기능을 추가했습니다.
- 툴킷 모듈 전반의 공통 스타일, 번역, 미리보기, 실행 안정성을 개선했습니다.
- 사용자 특성 배경 파일을 업데이트에 안전한 `Interface` 하위 사용자 지정 폴더로 이동했습니다.
