# DDingUI Toolkit Changelog

## 2.2.4

Release date: 2026-10-20
Scope: Changes after the 2.2.3.3 release commit bae76ed.

### 한국어

- **일정 달력:** 접속한 캐릭터들의 개인·길드·커뮤니티 일정을 한 달 화면에서 확인할 수 있습니다. 날짜별 상세 일정과 축제·주간 초기화도 표시합니다. 편의 기능에서 켜고 `/ddt schedule` 또는 전용 미니맵 버튼으로 엽니다.
- **달력 표시:** 캐릭터별 표시와 창 위치·크기를 조절할 수 있습니다. 일정이 많은 날과 6주 달력에서 내용이 겹치지 않도록 정리하고, 게임 글꼴에 없는 초기화 기호를 제거했습니다.
- **축제 조회:** 일부 축제에 시작·종료 날짜가 없어 일정 전체를 불러오지 못하던 문제를 수정했습니다.

### English

- **Schedule calendar:** View personal, guild, and community events collected from characters you have logged in on a monthly calendar. It also shows daily details, holidays, and the weekly reset. Enable it under Utility, then open it with `/ddt schedule` or its minimap button.
- **Calendar layout:** Choose visible characters and adjust the window position and scale. Fixed overlapping entries on busy days and six-week months, and removed a reset symbol missing from the game font.
- **Holiday loading:** Fixed a missing holiday start or end date preventing the calendar from loading all events.

## 2.2.3.3

Release date: 2026-10-18
Scope: Changes after the 2.2.3.2 release commit 8ad94b7.

### 한국어

- **공허핵 도우미:** 키식스 전리품 목록을 불러오지 못하던 문제를 수정했습니다. 게임의 모험 안내서에서 현재 보스 번호를 읽어 BIS 선택 화면에 전리품을 표시합니다.

### English

- **Voidcore Helper:** Fixed Kith'ix loot failing to load. The BIS selection screen now reads the encounter ID from the current Encounter Journal data to show its loot.

## 2.2.3.2

Release date: 2026-10-18
Scope: Changes after the 2.2.3.1 release commit d9d66fa.

### 한국어

- **캐릭터 위치 마커:** 사거리 밖 색상 변경을 탱커·근딜·원딜·힐러 전문화별로 설정할 수 있습니다. 기존 ‘근딜 전문화일 때만 거리 체크’ 설정은 근딜만 켜진 상태로 옮깁니다.
- **파티 트래커:** 편집 모드에서 파티 트래커 본체와 분리 마나바의 위치 조정 항목이 사라지던 문제를 수정했습니다.

### English

- **Character Position Marker:** Added separate out-of-range color checks for tank, melee DPS, ranged DPS, and healer specializations. The previous melee-only setting migrates to melee-only range checking.
- **Party Tracker:** Fixed the Party Tracker and separate mana bar disappearing from edit mode.

## 2.2.3.1

Release date: 2026-10-15
Scope: Changes after the 2.2.3 release commit db31934.

### 한국어

- **공허핵 도우미:** 키식스 이름의 한글 표시를 보완하고, 모험 안내서 정보가 늦게 불러와져도 키식스 전리품을 조회하도록 수정했습니다.
- **효과음:** 게임에 없는 내장 효과음 경로로 발생하던 LibSharedMedia 오류를 수정했습니다. 현재 게임에서 확인되는 소리만 선택 목록에 표시합니다.

### English

- **Voidcore Helper:** Added a Korean fallback name for Kith'ix and fixed its loot lookup when Encounter Journal data is not ready yet.
- **Sounds:** Fixed LibSharedMedia errors from unavailable built-in sound paths. Only sounds found in the current game client appear in the selection list.

## 2.2.3

Release date: 2026-10-15
Scope: Changes after the 2.2.2 release commit fd18a69.

### 한국어

- **12.1.5 지원:** 새 게임 버전을 지원하고 장비 레벨 표시와 자동 수리가 변경된 게임 API에서도 작동하도록 수정했습니다.
- **공허핵 도우미:** 키식스 보스를 공격대 BIS 출처에 추가했습니다. 키식스 전리품 목록과 공허핵 사용 판단에 반영됩니다.
- **아이템 레벨:** 장비의 강화 단계를 표시합니다. 글자색을 장비 품질에 맞추고 무기·보조무기 칸의 표시 위치를 정리했습니다.
- **준비 확인:** 증강 룬과 반투스 룬을 선택 항목으로 표시합니다. 개인·공격대 창에서 상태를 확인할 수 있으며, 선택 항목은 준비 완료 판정과 부족 인원 수에 포함되지 않습니다.

### English

- **Patch 12.1.5:** Added support for the new game version and updated Item Level and Auto Repair for the changed game APIs.
- **Voidcore Helper:** Added Kith'ix as a raid BIS source. Its loot is now available when choosing targets and evaluating a Voidcore roll.
- **Item Level:** Added gear upgrade progress, matched its text color to item quality, and adjusted placement for weapon and off-hand slots.
- **Ready Check:** Added augment and Vantus runes as optional items in the personal and raid windows. They do not affect readiness or missing-player counts.

## 2.2.2

Release date: 2026-10-11
Scope: Changes after the 2.2.1 release commit fb92f37 through this release.

### 한국어

- **설정 정리:** 안내문·설명 툴팁·빈 탭·중복 사용 스위치를 제거했습니다. 관련 소리 설정과 작은 탭을 묶고, 표현 방식에 따라 효과가 있는 옵션만 표시합니다. 모듈 머리줄의 활성화 스위치 하나로 동작합니다.
- **좁은 설정창:** 긴 세부 탭 이름이 잘리지 않도록 창 너비와 글자 길이에 맞춰 줄을 나눕니다. 창 크기를 바꿔도 선택한 탭을 유지하며 다시 배치합니다.
- **설정창 열기:** 등장 모션 중 세부 탭이 세로로 쌓여 다른 영역과 겹치던 문제를 수정했습니다.
- **전투 타이머:** 소수 부분 글꼴 크기를 따로 조절할 수 있습니다. 0은 기존 자동 크기입니다. 색상 선택 시 글자 불투명도가 반대로 저장되던 문제를 수정하고 색상 변경을 즉시 반영합니다. 이미 투명해진 기존 설정은 글자 불투명도를 100%로 한 번 복구해 주세요.
- **준비 확인:** 도핑·장비 상태를 전용 아이콘과 남은 시간으로 표시하고 개인 준비창과 공격대 응답 요약을 간결하게 정리했습니다. 공격대 창에는 미준비·응답 대기 이름을 따로 표시하며, 모두 준비되면 자동으로 열린 창은 닫힙니다.
- **편집 모드:** 위치 슬라이더·잠금·위치 초기화 버튼을 공용 편집 모드로 통일했습니다. 파티 신청 알림의 위치 저장을 고치고 우편 알림 두 디자인도 편집 대상에 추가했습니다. 기존 배치는 유지합니다.
- **설정 적용:** 파티 트래커의 기본 활성화와 분리 마나바·블러드 아이콘의 즉시 변경, 아이템 레벨 기본값 복원, 사망 알림 글꼴, 커서 정사각형 텍스처 보존, 메모장 버튼 갱신을 수정했습니다. 사망·내구도 알림은 소리를 따로 고르지 않아도 기본 경보음을 재생합니다. 기존 표시 지연·추적 조건·판정 주기·글꼴·표시 레이어 설정을 화면에 추가했습니다. 타겟 스펠 소리는 대상 판정이 공개 값일 때만 재생하며 비밀값은 사용하지 않습니다.
- **쐐기돌 도우미:** 모듈과 하위 어픽스 진단, 전용 메뉴·명령어·로드 참조를 삭제했습니다.

- **공허핵 도우미:** 영웅·신화 공격대와 쐐기 밖의 공허핵 보상은 BIS·진입 확인·개별 구렁/사냥 설정과 관계없이 자동 포기합니다. 진입 확인창은 영웅·신화 공격대와 쐐기에서만 표시합니다. 해당 콘텐츠의 기존 BIS 판정과 쐐기 10단 조건, 일반 전리품은 유지합니다.

### English

- **Settings:** Removed explanatory copy, help tooltips, empty tabs and duplicate enable switches. Related sound controls and small sections are grouped together, and controls are hidden when the selected design cannot use them. The module-header switch is the sole enable control.
- **Narrow settings windows:** Section tabs wrap to fit their labels and the available width. Resizing preserves the selected tab and updates the layout without recreating controls.
- **Opening settings:** Fixed section tabs stacking vertically and overlapping other areas during the opening animation.
- **Combat Timer:** Added a separate fractional-seconds font size; 0 retains automatic sizing. Fixed inverted text opacity when choosing colors and applied color changes immediately. If an existing timer is already transparent, set its text opacity to 100% once to restore it.
- **Ready checks:** Added dedicated consumable/equipment icons and remaining time, with compact personal checks and raid response summaries. Raid windows list not-ready and pending players separately; automatically opened windows close when all readiness checks pass.
- **Edit mode:** Moved position, lock and position-reset controls into the shared editor. Fixed saving Party Application Alert positions and added both Mail Alert designs while preserving existing placement.
- **Setting updates:** Fixed Party Tracker activation and live updates for separate mana bars and the Bloodlust icon, Item Level reset, Death Alert font selection, square cursor-texture persistence and Notepad button refresh. Death and durability alerts now use a default warning sound when no sound is selected. Exposed existing delay, tracking conditions, polling, font and frame-layer settings. Target Spell sounds use only public target checks; secret values are never branched on.
- **Keystone Helper:** Removed the module, its affix diagnostics, dedicated menu, commands and load references.

- **Voidcore Helper:** Automatically declines Voidcore rewards outside Heroic/Mythic raids and Mythic Keystones regardless of BIS, entry consent or individual Delve/Prey settings. Entry confirmation appears only in Heroic/Mythic raids and Keystones. Existing BIS checks, the Keystone +10 threshold and ordinary loot are unchanged.

## 2.2.1

Release date: 2026-10-06
Scope: Changes after the 2.2.0 release commit 2a90459 through this release.

### English Patch Notes

- **Edit Mode:** Added the shared edit remote with frame selection, X/Y entry, keyboard nudging, undo/redo, grid and snapping controls. Open it from the settings title bar or `/ddt edit`. Footer buttons are centered and shrink when space is limited; entering combat exits edit mode, and a normal exit returns to the settings window when it was open.
- **Combat Timer:** Added one- or two-digit fractional seconds. The combat timer and combat-state alerts use the same combat start/end state, and the final timer value stops at the end of combat rather than including the end-confirmation delay.
- **Party Tracker Commands:** Removed `/pt`, `/partytracker`, `/ddt party` and `/ddt tracker`. Party tracking, its settings and its edit-mode frames remain available.
- **Settings Window:** The window can be moved partly off screen while keeping a visible area available for dragging. The title-bar edit button shows whether edit mode is active.

### Korean Patch Notes

- **편집 모드:** 프레임 선택, X/Y 입력, 키보드 이동, 실행 취소·다시 실행, 격자·스냅을 제공하는 공통 리모컨을 추가했습니다. 설정창 제목줄이나 `/ddt edit`로 열 수 있습니다. 하단 버튼은 가운데 정렬되며 공간이 좁으면 너비를 줄입니다. 전투에 들어가면 종료되며, 설정창에서 진입했다면 일반 종료 후 설정창으로 돌아갑니다.
- **전투 타이머:** 소수점 한 자리·두 자리 표시를 추가했습니다. 전투 타이머와 전투 상태 알림이 같은 시작·종료 기준을 사용하며, 최종 시간에 전투 종료 확인을 위한 대기 시간이 더해지지 않도록 조정했습니다.
- **파티트래커 명령어:** `/pt`, `/partytracker`, `/ddt party`, `/ddt tracker`를 제거했습니다. 파티 추적 기능과 설정, 편집 모드 프레임은 유지합니다.
- **설정창:** 화면 밖으로 일부 이동할 수 있으며, 다시 드래그할 수 있는 영역은 남겨 둡니다. 제목줄의 편집 버튼에서 현재 편집 상태를 확인할 수 있습니다.

## 2.2.0

Release date: 2026-09-30

### Option Changes

- **Settings Window:** Redesigned the window with rounded corners. Categories, pages and details sit on separate rounded cards, and the selected category and page are marked with an accent pill that slides to each new selection. Row hover highlights fade in and out, module status shows an accent ring when enabled and a grey ring when disabled, section headings have a ring marker, and settings fade in one after another when you switch pages.
- **Settings Window:** The title bar shows the DDingUI logo rings, which link together each time the window opens, followed by the DDingUI wordmark and the Toolkit name.
- **Settings Window:** Added a 'GUI Scale' control to the left of the title bar's close button. Drag it or use the mouse wheel to scale the window from 50% to 150%; the scale is saved and kept when the window reopens.
- **Settings Window:** Sliders use a fixed-width track with a 28px click area and a larger solid thumb that grows and turns white on hover; values use a larger font. Buttons, checkboxes, input fields, dropdowns, color buttons, the search box, dashboard cards and the profile code window use rounded corners.

- **Chat Messages:** All Toolkit chat messages now use the same "DDingUI Toolkit" prefix. Target Spell, Character Position Marker, Combat Timer, Focus Interrupt and affix diagnostics previously used their own labels, and death alert chat messages had no prefix. Error messages keep the prefix colors and show only the message text in red.

- **Notepad / Affix Diagnostics:** Notepad windows and the affix report window use rounded corners and the Toolkit accent title color.

- **Raid Party Tooltip:** Hover over role or armor counts in the recruitment panel to see class icons, class-colored names, and member counts. Open tooltips update with roster and specialization changes.

- **Talent Background:** Fixed a missing translation warning when opening the preview without a selected background. Korean and English now display the empty-selection message correctly.
- **Talent Background:** The Apply button briefly shows 'Applied' after a background is applied. The image list scroll bar has a wider click area and highlights on hover.

- **Raid Party Tooltip:** Missing synergy names in the recruitment composition panel now use the providing class's color, matching the class information in their tooltips.
- **Raid Party Tooltip:** Added Warlock Demonic Gateway and Death Knight Death Grip to missing synergies. Their class icons and colors are shown while the corresponding class is absent; the list now accommodates all 13 entries.

### 옵션 변경

- **설정 창:** 둥근 모서리 디자인으로 개편했습니다. 카테고리·페이지·상세 영역을 각각 둥근 카드로 나누고, 선택한 카테고리와 페이지는 새 선택 위치로 미끄러지는 악센트 알약으로 표시합니다. 행에 마우스를 올리면 강조가 부드럽게 나타나고 사라지며, 모듈 상태는 켜짐이면 악센트색 고리, 꺼짐이면 회색 고리로 표시합니다. 섹션 제목에 고리 표식을 붙이고, 페이지를 바꾸면 설정 항목이 차례로 나타납니다.
- **설정 창:** 제목줄에 DDingUI 로고 고리를 표시하며, 창을 열 때마다 두 고리가 맞물리는 애니메이션이 재생됩니다. 그 옆에 DDingUI 워드마크와 Toolkit 이름을 표시합니다.
- **설정 창:** 제목줄 닫기 버튼 왼쪽에 'GUI 크기' 조절을 추가했습니다. 드래그나 마우스 휠로 창 크기를 50~150%로 조절하며, 설정한 크기는 저장되어 창을 다시 열어도 유지됩니다.
- **설정 창:** 슬라이더를 고정 너비 트랙, 28px 클릭 영역, 마우스를 올리면 커지고 흰색으로 바뀌는 큼직한 단색 손잡이로 바꾸고 값 글자도 키웠습니다. 버튼·체크박스·입력칸·드롭다운·색상 버튼·검색창·대시보드 카드·프로필 코드 창에 둥근 모서리를 적용했습니다.

- **채팅 메시지:** 모든 Toolkit 채팅 메시지가 같은 'DDingUI Toolkit' 접두사를 사용합니다. 타겟 스펠·캐릭터 위치 마커·전투 타이머·주시 차단·어픽스 진단은 각자 다른 표기를 쓰고 있었고, 사망 알림 채팅 메시지에는 접두사가 없었습니다. 오류 메시지는 접두사 색상을 유지하고 본문만 빨간색으로 표시합니다.

- **메모장 / 어픽스 진단:** 메모장 창과 어픽스 보고서 창에 둥근 모서리와 Toolkit 악센트색 제목을 적용했습니다.

- **공격대 파티 툴팁:** 모집 구성창의 역할·방어구 인원수에 마우스를 올리면 직업 아이콘·직업 색상과 직업별 인원수를 표시합니다. 공대원이나 전문화 정보가 바뀌면 열린 툴팁도 함께 갱신됩니다.

- **특성창 배경:** 선택된 배경 없이 미리보기를 열 때 발생하던 번역 누락 오류를 수정했습니다. 한국어·영어에서 선택 없음 안내를 정상 표시합니다.
- **특성창 배경:** 배경을 적용하면 적용 버튼에 잠시 '적용됨'을 표시합니다. 이미지 목록 스크롤바의 클릭 영역을 넓히고 마우스를 올리면 강조되도록 했습니다.

- **공격대 파티 툴팁:** 모집 구성창의 '없는 시너지' 이름을 해당 직업 색상으로 표시하여 툴팁의 직업 정보와 구분을 맞췄습니다.
- **공격대 파티 툴팁:** 없는 시너지에 흑마법사의 '악마의 관문'과 죽음의 기사의 '죽음의 손아귀'를 추가했습니다. 해당 직업이 없으면 직업 아이콘·색상으로 표시하며, 최대 13개 항목이 모두 나오도록 목록을 확장했습니다.

## 2.1.8

Release date: 2026-09-22

### Option Changes

- **Voidcore Helper:** Added separate Delve and Prey auto-decline toggles, enabled by default. With non-BIS auto-decline enabled, recognized Voidcore offers from these activities are declined without instance-entry confirmation or BIS checks. Ordinary loot and dungeon/raid BIS rules are unchanged.

- **Raid Party Tooltip:** Added a Recruitment Panel option for raid leaders. The applicant view shows joined members' tank/melee/ranged/healer counts, armor counts, and missing class-based synergies, in group-finder / composition / Raider.IO order. Unavailable role or specialization data is shown separately; recruitment end, combat, and closing the finder hide the panel.
  The panel chooses its side once when opened; Raider.IO tooltip visibility, width changes, and roster refreshes no longer move it between sides.
  Fixed same-realm specialization matching and added sequential inspection of unclassified, inspectable members while the panel is open. Received information is retained; combat and manual inspections pause automatic requests. Members with no available information remain unclassified.

- **Raid Preparation:** Shows not-ready and waiting-for-reply player names separately below the status heading, each in its class color. Long lists show a remaining count, with the full class-colored names available on hover. Names update as players respond.

- **Settings Window:** Added opening and closing motion and unified window titles, edit-mode branding, and minimap tooltip labels. Settings remain accessible when an older shared library is loaded.

### 옵션 변경

- **공허핵 도우미:** '구렁 자동 포기'와 '사냥 자동 포기' 옵션을 추가했습니다(기본 켜짐). 비-BIS 자동 포기가 켜져 있으면 해당 콘텐츠로 확인된 공허핵 보상을 진입 확인이나 BIS 설정과 관계없이 포기합니다. 일반 전리품과 기존 던전·레이드 BIS 판단은 유지합니다.

- **공격대 파티 툴팁:** 공대장용 '모집 구성창 표시' 옵션을 추가했습니다. 신청자 화면에서 합류한 인원의 탱커·근딜·원딜·힐러 수, 방어구별 인원, 없는 직업 시너지를 확인합니다. 모집창 → 공대 구성창 → Raider.IO 순으로 배치하며, 미확인 역할·전문화는 따로 표시합니다. 모집 종료·전투 진입·모집창 닫기 시 함께 숨깁니다.
  구성창의 좌우 배치는 열 때 한 번만 결정하여 Raider.IO 툴팁 표시·숨김·너비 변경이나 인원 갱신으로 위치가 바뀌지 않습니다.
  같은 서버의 전문화 정보가 누락되던 이름 매칭을 수정했습니다. 구성창이 열려 있을 때 조회 가능한 미확인 인원을 순차 확인하고 받은 정보를 유지합니다. 전투·수동 살펴보기 중에는 자동 조회를 쉬며, 정보를 얻을 수 없는 인원은 미확인으로 남깁니다.

- **공격대 준비:** 상태 제목 아래에 미준비·응답 대기 인원의 이름을 나누어 각 직업 색상으로 표시합니다. 긴 명단은 '외 N명'으로 줄이고 마우스를 올리면 직업 색상이 적용된 전체 이름을 확인할 수 있습니다. 응답하면 명단도 갱신됩니다.

- **설정 창:** 열기·닫기 모션을 추가하고 창 제목·편집 모드·미니맵 안내 표기를 통일했습니다. 이전 공용 라이브러리를 사용 중이어도 설정 창은 정상적으로 열립니다.

## 2.1.7

Release date: 2026-09-14

### Option Changes

- **Mail Alert:** Added an Alert Design selector for the original faction banner or the new mail seal. Existing profiles retain the faction banner. The seal has its own motion toggle; both designs share position, scale, duration and sound settings, and can be switched in live preview.

- **Bloodlust Timer:** Replaced the system crest with a symmetric mask. Mask and eyes/forehead colors and opacity can be changed independently; existing custom colors are preserved. Restored the original centered title, font size, and ring/crest proportions without changing the timer's icon or text settings.

- **Ready Check Assistant:** Personal readiness now uses matching line icons for flask, food, augment rune, weapon enhancement, and durability, with specialization and talents above. Shows remaining buff time or unknown status, includes missing consumables in reports, and supports widths from 560 to 900. Existing position, scale, action-button and close behavior settings remain.

- **Raid Preparation:** Replaced the large grid and gauges with a compact response summary and a scrollable list of outstanding checks. Automatically opened windows fade out after everyone is ready and all enabled checks pass; entering combat hides the window. Manually opened windows stay open on completion. The optional end-of-check timeout can still close incomplete results.

- **Calendar Invite Alert:** Today's upcoming events are grouped into one notification with a time-and-title list and one sound. Pending-invitation alerts now also exclude already-started events, including combat/loading deferrals; queued sounds recheck eligibility before playing.

- **Raid Groups:** Both balancing modes now reserve an equal number of parties on each side even when the raid needs an odd number of parties. For example, 25 players use parties 1-2-3 / 4-5-6 in consecutive mode.

- **Affix Diagnostics:** Added opt-in `/ddt affix on`, `mark`, `off`, and `report` commands. Reports are cleared by reload. This is a diagnostic tool, not an affix countdown timer.

### 옵션 변경

- **우편 알림:** 알림 디자인에서 기존 진영 배너와 새 편지 인장을 선택할 수 있습니다. 기존 사용자는 진영 배너를 유지하며, 인장형에는 별도 모션 ON/OFF를 제공합니다. 위치·크기·표시 시간·소리 설정은 공통으로 사용하고 실시간 미리보기에서 디자인을 전환할 수 있습니다.

- **블러드 타이머:** 시스템 문양을 대칭 가면으로 교체했습니다. 가면과 눈·이마의 색상·투명도를 따로 조절할 수 있으며 기존 사용자 색상은 유지합니다. 모션의 중앙 문구 배치·글자 크기·링과 문양 비율은 기존대로 복원하고 타이머 본체의 아이콘·텍스트 설정은 유지합니다.

- **준비 확인 도우미:** 개인 영약·음식·증강 룬·무기 강화·내구도를 통일된 선형 아이콘으로 표시하고 전문화·특성은 상단으로 분리했습니다. 버프 남은 시간과 확인 불가 상태를 표시하며, 소모품 부족도 파티 보고에 포함합니다. 너비 범위는 560~900으로 확장하고 기존 위치·배율·버튼·닫힘 설정은 유지합니다.

- **공격대 준비:** 큰 표와 게이지 대신 가로형 응답 요약과 부족한 항목 목록을 표시합니다. 자동으로 열린 창은 전원이 준비하고 활성 점검을 통과하면 잠시 후 사라지며, 전투 진입 시 즉시 숨깁니다. 수동으로 연 창은 완료 시 유지하고, 미완료여도 준비 확인 종료 후 닫는 옵션은 유지합니다.

- **달력 초대 알림:** 오늘 남은 일정을 시간·제목 목록으로 한 알림에 모아 표시하고 효과음도 한 번만 재생합니다. 미확인 초대 알림에도 지난 일정 제외를 적용하여 전투·로딩 후 재개 시 이미 시작한 일정은 건너뛰고, 대기 중인 효과음도 재생 직전에 확인합니다.

- **공격대 그룹 관리:** 필요한 파티 수가 홀수여도 양쪽 조에 같은 수의 파티를 확보하도록 균형 배치를 조정했습니다. 예를 들어 25인 공대의 연속 배치는 1·2·3 / 4·5·6파티를 사용합니다.

- **어픽스 진단:** 직접 켜서 사용하는 `/ddt affix on`, `mark`, `off`, `report` 명령을 추가했습니다. 기록은 리로드하면 지워지며, 아직 어픽스 카운트다운 타이머는 아닙니다.

## 2.1.6

Release date: 2026-09-06

### New Modules

- **Calendar Invite Alert:** Added login and new-invitation notifications based on unanswered calendar invites. Repeated count updates are deduplicated, alerts can wait until combat ends, and answered or cancelled invites clear the notice. The module starts disabled and is included in the one-time new-module popup.

### 신규 모듈

- **달력 초대 알림:** 접속 시 미응답 달력 초대와 새 초대를 알려줍니다. 같은 개수의 중복 알림을 방지하고 전투 중에는 보류하며, 모두 응답하거나 취소되면 알림을 정리합니다. 기본 비활성 상태로 시작하고 신규 모듈 안내에 표시됩니다.

### Option Changes

- **Calendar Invite Alert:** Notifications now start after loading screens finish; interrupted notices resume after loading.
- **Targeted Spells:** Added icon, duration-bar, and icon/text/icon display modes with shared stable sorting.
- **Combat State Alert:** Added an option to exclude Delves.

- **Calendar Invite Alert:** Added Today's Events and a separate test button. Today's personal, guild and community events show their server-time start and title in chronological order, without repeating unchanged events during the session. System events and declined or removed invitations are excluded.
- Added Calendar Invite Alert under Alerts, with screen/sound/chat/taskbar notifications, combat deferral, motion, font/color, duration, position, edit-mode preview, and a calendar-open button. Sounds use the shared Sound Manager.
- Calendar alerts use the calm party-alert motion with a calendar emblem, muted mint rails and pale gold accents. Motion OFF keeps a static notification; existing custom colors are preserved.
- **Ready Check Assistant:** Reworked the panel into a status summary, separate current/expected talent rows, and a durability gauge with a repair threshold. The default width is now 440px; existing width, position, scale, and button visibility settings are preserved.
- Talent and repair issues appear together, with unset or unavailable loadouts distinguished from a match. Group reports include both issues when applicable.

### 옵션 변경

- **달력 초대 알림:** 로딩 종료 후 알림을 시작하고 로딩으로 중단된 알림은 화면이 돌아온 뒤 다시 표시합니다.
- **타겟 스펠:** 아이콘, 지속시간 바, 아이콘·텍스트·아이콘 표시 모드와 공통 정렬을 추가했습니다.
- **전투 시작·종료 알림:** 구렁에서 제외하는 옵션을 추가했습니다.

- **달력 초대 알림:** 오늘 일정 알림과 별도 테스트 버튼을 추가했습니다. 개인·길드·커뮤니티의 오늘 일정을 서버 시간순으로 시작 시각과 제목을 표시하고, 접속 중 같은 일정은 반복 알림하지 않습니다. 시스템 일정과 거절·제외된 초대는 표시하지 않습니다.
- 알림 분류에 달력 초대 알림을 추가하고 화면·소리·채팅·작업 표시줄 알림, 전투 종료 후 알림, 모션·글꼴·색상·표시 시간·위치·편집모드 미리보기 및 달력 열기 버튼을 제공합니다. 효과음은 공통 사운드 관리자를 사용합니다.
- 달력 알림에 파티 알림 계열의 차분한 모션과 달력 표식, 은은한 민트색 선·연한 금색 장식을 적용했습니다. 모션을 끄면 정적으로 표시되며 기존 사용자 지정 색상은 유지합니다.
- **준비 확인 도우미:** 상태 요약, 현재·기준 특성 비교, 수리 기준선이 있는 내구도 표시로 패널을 개편했습니다. 기본 너비는 440px이며 기존 너비·위치·배율·버튼 표시 설정은 유지합니다.
- 특성 불일치와 수리 필요를 함께 표시하고, 특성 미설정·확인 불가를 기준 일치와 구분합니다. 파티 알림에도 동시에 발생한 문제를 모두 포함합니다.

## 2.1.5

Release date: 2026-08-29

## English

### New Modules

- **Voidcore Helper:** Added a Nebulous Voidcore advisor for Heroic/Mythic raid bosses and Mythic Keystone +10 or higher. It tracks specialization-specific BIS targets, shows remaining eligible loot and an equal-weight estimated chance, and can automatically decline ineligible rewards after per-instance approval.

### Option Changes

- Added a BIS setup browser that selects targets directly from seasonal dungeon and raid-boss loot tables. It keeps equippable loot for the selected specialization while excluding recipes, housing decor, and cosmetic-only entries.
- Added separate toggles for the Voidcore advisor, remaining-loot list, non-BIS auto-decline, and the instance-entry approval prompt. The new module starts disabled for existing profiles and appears in the one-time new-module notice.
- Moved Raid Loot Pass and Voidcore Helper into the Utility category.
- Added a tooltip to custom sound paths explaining that paths begin below the WoW `_retail_` folder, with `Interface\abc.ogg` as an example.

### Fixes

- Kept Combat Timer running when the player dies or enters Spirit of Redemption while the group remains in combat.
- Removed direct overrides of Blizzard inspect and talent-frame state that could contribute to protected-action taint.
- Improved Voidcore loot-table loading when item specialization metadata is not yet available, without restoring recipes or cosmetic-only entries.

## 한국어

### 신규 모듈

- **공허핵 도우미:** 영웅·신화 공격대 보스와 10단 이상 쐐기에서 성운의 공허핵 사용 여부를 판단합니다. 전문화별 BIS 목표, 남은 획득 가능 전리품과 동일 확률 기준 예상 획득률을 표시하고, 인스턴스별 승인을 받은 뒤 조건에 맞지 않는 보상을 자동 포기할 수 있습니다.

### 옵션 변경

- 시즌 던전과 공격대 보스 전리품 표에서 직접 전문화별 BIS를 선택하는 설정 창을 추가했습니다. 선택한 전문화가 착용할 수 있는 장비만 남기고 도안, 하우징 장식 및 장식 전용 아이템은 제외합니다.
- 공허핵 판단창, 남은 전리품 목록, 비-BIS 자동 포기와 인스턴스 진입 승인 팝업을 각각 설정할 수 있습니다. 새 모듈은 기존 프로필에서 비활성 상태로 시작하며 최초 한 번 신규 모듈 안내에 표시됩니다.
- 레이드 전리품 자동 포기와 공허핵 도우미를 편의 기능 분류로 이동했습니다.
- 커스텀 사운드 경로에 WoW `_retail_` 폴더 아래부터 입력한다는 도움말과 `Interface\abc.ogg` 예시를 추가했습니다.

### 수정 사항

- 플레이어가 사망하거나 구원의 영혼 상태가 되어도 파티가 전투 중이면 전투 타이머가 이어지도록 수정했습니다.
- 보호된 동작 오염을 유발할 수 있던 Blizzard 살펴보기 함수 및 특성창 상태 직접 덮어쓰기를 제거했습니다.
- 아이템 전문화 정보가 아직 준비되지 않은 경우에도 정상 장비가 공허핵 전리품 표에서 누락되지 않도록 개선했으며, 도안과 장식 전용 아이템 제외는 유지했습니다.

## 2.1.4

Release date: 2026-08-26

## English

### New Modules

- **Raid Defensive Tracker:** Added a WoW 12.1 engine-driven icon tracker for received Innervate, Time Spiral, Spatial Paradox, Power Infusion, Anti-Magic Zone, Darkness, Zephyr, Aura Mastery, Mass Barrier, Power Word: Barrier, Spirit Link Totem, and Rallying Cry effects.

### Option Changes

- Added a Group Movement Buffs section to Raid Defensive Tracker for received Stampeding Roar, Wind Rush Totem, and Piercing Howl effects, including per-effect toggles, icons, and sound settings.
- Added spell icons to every tracked-effect option, plus separate sound, custom sound path, and output-channel settings for each buff.
- Added a global default sound for Raid Defensive Tracker; a configured per-buff sound overrides it, while `Use Global Setting` inherits the shared sound and channel.
- Fixed Raid Defensive Tracker borders appearing only in preview by drawing four explicitly sized inner edge lines on an isolated layer above the cooldown. Border setup now finishes before Blizzard marks duration text properties as secret, so a rejected text write cannot skip it. No filled backing rectangle remains for the aura provider to expand across the screen.
- Removed the redundant live icon background layer and its color option. This prevents Blizzard's 12.1 AuraContainer from detaching the layer as either a full-screen dim or an icon-sized black box at screen center.
- Corrected Raid Defensive Tracker's duration swipe so it depletes in the intended direction as the received buff expires.
- Suppressed both the Bloodlust ready sound caused by exhaustion cleanup and the combat-end sound after a successful raid-boss kill. The combat-end visual and normal exhaustion-expiry alerts remain unchanged.
- Grouped Raid Party Tooltip class counts by tank, damage, and healer roles. Each role icon and heading now occupies its own line, followed by indented class-icon counts on the next line for easier scanning.
- Fixed manual Raid Group Manager ordering by resolving fresh raid indices and waiting for each roster update between the three bridge swaps, so changes within the same party are applied instead of collapsing into a no-op.
- Added a uniform icon zoom control plus separate horizontal and vertical crop controls to Raid Defensive Tracker, shared by preview and live aura icons. Cropping now trims the actual icon bounds without stretching the remaining image, allowing rectangular icons while zoom remains independent.
- Added position locking and direct drag placement while settings preview is active, and synchronized its coordinates with the global edit-mode anchor and position controls. Fixed preview-source detection so unlocking position enables direct dragging without conflicting with the global edit-mode mover.
- Added separate external-support and raid-defensive toggles plus icon size, spacing, growth direction, scale, layer, duration swipe and text, font, border, color, position, settings preview, and edit-mode anchor settings.

## 한국어

### 신규 모듈

- **공생기 추적:** 내 캐릭터에게 적용된 정신 자극, 시간의 와류, 공간의 역설, 마력 주입과 대마법 지대, 어둠, 미풍, 오라 숙련, 대규모 방벽, 신의 권능: 방벽, 정신의 고리 토템 및 재집결의 함성을 WoW 12.1 엔진 기반 아이콘으로 표시합니다.

### 옵션 변경

- 공생기 추적에 이동 지원기 구역을 추가하고, 내가 받는 쇄도의 포효·바람 질주 토템·날카로운 고함을 개별 활성화·아이콘·사운드 설정과 함께 추적합니다.
- 각 추적 효과 옵션에 주문 아이콘을 표시하고, 버프마다 효과음·사용자 사운드 경로·출력 채널을 따로 지정할 수 있게 했습니다.
- 공생기 추적에 전체 기본 사운드를 추가했습니다. 버프별 사운드를 지정하면 개별 설정을 우선하고, `전체 설정 사용`이면 공통 사운드와 채널을 상속합니다.
- 공생기 추적 테두리가 미리보기에만 표시되던 문제를 수정하고, 쿨다운 위의 독립 레이어에 크기를 명시한 안쪽 상·하·좌·우 선 4개로 표시하도록 변경했습니다. Blizzard가 지속시간 텍스트를 제한하기 전에 테두리 설정을 끝내므로 텍스트 설정이 거부되어도 건너뛰지 않으며, 오라 컨테이너가 화면 전체로 늘릴 수 있는 채워진 후면 사각형은 남기지 않습니다.
- 불필요한 라이브 아이콘 배경 레이어와 배경색 옵션을 제거해, WoW 12.1 오라 컨테이너에서 해당 레이어가 화면 전체 암전 또는 화면 중앙의 아이콘 크기 검정 상자로 분리되어 표시되던 문제를 수정했습니다.
- 공생기 추적의 지속시간 스와이프가 버프 만료 방향과 반대로 움직이던 문제를 수정했습니다.
- 레이드 보스 처치 성공 후 소진 효과가 정리될 때 발생하는 블러드 준비 완료 소리와 전투 종료 효과음을 모두 억제했습니다. 전투 종료 화면 연출과 일반 소진 만료 알림은 그대로 유지됩니다.
- 공격대 파티 툴팁의 직업별 인원을 방어·공격·치유 담당으로 나누고, 역할 아이콘과 제목은 한 줄에, 해당 역할의 직업 아이콘·이름·인원은 다음 들여쓰기 줄에 표시하도록 변경했습니다.
- 공격대 그룹 관리에서 같은 파티 안의 수동 순서를 바꿀 때 최신 공격대 인덱스를 확인하고 3번의 브리지 교환 사이마다 명단 갱신을 기다리도록 해, 적용이 무효화되던 문제를 수정했습니다.
- 공생기 추적에 비율을 유지하는 아이콘 확대와 가로·세로 크롭을 각각 조절하는 옵션을 추가하고 미리보기와 실제 오라 아이콘에 동일하게 적용했습니다. 크롭은 남은 이미지를 늘리지 않고 실제 표시 영역을 잘라 직사각형 아이콘을 만들며, 아이콘 확대는 별도로 적용됩니다.
- 위치 잠금과 설정 미리보기 중 직접 드래그 이동을 추가하고, 좌표 설정값을 전역 편집 모드 앵커와 양방향 동기화했습니다. 미리보기 진입 경로를 구분해 위치 잠금을 풀면 직접 드래그가 활성화되고 전역 편집 모드 앵커와 충돌하지 않도록 수정했습니다.
- 외부 지원기와 공생기를 나눈 개별 활성화 옵션 및 아이콘 크기, 간격, 확장 방향, 배율, 레이어, 지속시간 스와이프·텍스트, 글꼴, 테두리, 색상, 위치, 설정 미리보기와 편집 모드 앵커 설정을 추가했습니다.

## 2.1.3

Release date: 2026-08-25

## English

### New Modules

- **Raid Group Manager:** Added an editable 8-group raid layout with drag-and-drop placement, saved layouts, role balancing, and live subgroup application.
- **Raid Preparation:** Added a raid-ready overview for food, phials, augment runes, raid buffs, temporary weapon enhancements, durability, and ready-check status.
- **Raid Party Tooltip:** Added class icons plus class and armor-type counts for each subgroup when hovering group labels, empty slots, or raid members in the default Raid tab.

### Option Changes

- Added interleaved (`1·3·5 vs 2·4·6`) and contiguous (`1·2·3 vs 4·5·6`) two-side role-balancing modes to Raid Group Manager.
- Added a draggable on-screen Raid Group Manager button with visibility and raid-only options.
- Removed the extra layout-apply confirmation; reassignment now starts immediately after permission, combat, and roster validation.
- Strengthened Raid Group Manager class identification with brighter names, accent strips, borders, and subtle row tinting.
- Raid Group Manager auto-balance now flows from tanks/melee in each side's front parties to ranged/healers in its rear parties, balances class counts between both sides, concentrates healers in the last party, and applies the planned order within each live raid group.
- Added individual checks for Battle Shout, Power Word: Fortitude, Arcane Intellect, Mark of the Wild, Skyfury, and Blessing of the Bronze to Raid Preparation.
- Added LibDurability-compatible durability sharing with MRT and other supported addons.
- Added Toolkit-wide sound collision management with priority, sequential, and overlap modes, timing and fade controls, continuous-music suspension, and per-module importance adjustments.
- Added an opt-in Raid Auto Pass exclusion setting with individual choices for recipes, toys, mounts, battle pets, single non-set appearance unlock items, housing decor, and quest items. Equippable appearances, ensembles, and arsenals remain eligible for auto-pass.
- Harmonized operational popup windows and the Premade Group Filter with the main Toolkit's neutral palette, reduced saturated cyan surfaces, and kept Raid Group Manager above the main settings window.
- Fixed sequential sound playback so queued alerts keep their turn instead of expiring while earlier sounds are playing.
- Added separate Raid Party Tooltip options for member rows, empty slots, class icons, class counts, armor counts, and zero-member armor types.
- Rebuilt LFG and Party Recruitment Complete screen alerts with distinct calm motions: alternating applicant nodes gather from both sides, while a completed party settles before a soft center-out glow. Added looping motion previews, a motion on/off toggle, and detailed size, typography, and color controls.
- Rebuilt the low-durability warning in the same HUD style with a continuous gradient, outlined warning diamond, adjustable warning blink on/off and period, sizing, typography, and detailed colors.
- Added a one-shot `BLOODLUST` start HUD with a deep-crimson ritual banner, a pulsing red-gem seal, antique-gold filigree drawn outward, lower jewel punctuation, and drifting embers, plus a separate edit-mode anchor, preview button, and detailed motion, typography, position, and color options.
- Refined the Bloodlust start HUD palette with a denser black-crimson banner, darker aged-brass ornament, saturated blood-red seal and embers, and reduced highlight whitening so the gold no longer appears beige in game.
- Added a selectable **System Activation** Bloodlust HUD with independently rotating segmented rings, an original center crest, a magenta-black system panel, status nodes, and staged assembly, lock-in, pulse, and fade motion. Developed the crest into an original Bloodlust-inspired war mask with separately tintable frame and blood core layers, and expanded the system palette to eight colors while preserving the existing War Ritual design.
- Expanded Raid Party Tooltip to premade raid listings, with a separate display toggle plus the existing class icons, class counts, armor counts, and zero-count controls.
- Reworked Premade Group Filter so dungeon and party-composition changes refresh the visible results immediately, Bloodlust suitability is shown as `BL`/`BL+`/`BL-`, and Rating or Map sorting changes the actual row order while retaining Blizzard's order during restricted states.
- Updated Mythic+ Helper teleport overlays with secure spell buttons and safer cooldown and combat-state handling for WoW 12.1.

## 한국어

### 신규 모듈

- **공격대 그룹 관리:** 8개 공격대 그룹 편집, 드래그 배치, 편성 저장, 역할 균형 배치 및 실제 하위 그룹 적용 기능을 추가했습니다.
- **공격대 전투 준비:** 음식, 영약, 증강 룬, 공격대 버프, 임시 무기 강화, 내구도와 준비 확인 상태를 한 표에서 점검하는 기능을 추가했습니다.
- **공격대 파티 툴팁:** 기본 공격대 탭의 파티 제목, 빈 자리 및 공대원에 마우스를 올리면 해당 파티의 직업 아이콘과 직업별·방어구별 인원을 표시하는 기능을 추가했습니다.

### 옵션 변경

- 공격대 그룹 관리에 교차(`1·3·5 vs 2·4·6`) 및 연속(`1·2·3 vs 4·5·6`) 양 진영 역할 균형 배치 방식을 추가했습니다.
- 공격대 그룹 관리용 드래그 가능한 화면 버튼과 표시 여부·공격대 전용 표시 옵션을 추가했습니다.
- 별도 확인 창을 제거하고 권한·전투·명단 검증을 통과하면 그룹 재배치를 즉시 시작하도록 변경했습니다.
- 공격대 그룹 관리의 이름을 밝게 보정하고 직업색 강조선·테두리·옅은 배경색을 추가해 직업 구분을 강화했습니다.
- 공격대 그룹 관리 자동 배치를 각 진영의 앞쪽 탱커·근딜에서 뒤쪽 원딜·힐러로 이어지게 하고, 양쪽 직업 수를 균형 배치하며, 힐러를 마지막 파티에 집중하고 실제 공격대의 파티 내부 순서까지 계획표와 일치하도록 변경했습니다.
- 공격대 전투 준비에 전투의 외침, 신의 권능: 인내, 신비한 지능, 야생의 징표, 하늘격노, 청동용군단의 축복 개별 점검을 추가했습니다.
- MRT 등 호환 애드온과 내구도를 공유하는 LibDurability 연동을 추가했습니다.
- 툴킷 전체 사운드 충돌 관리에 우선순위·순차 재생·겹침 허용 방식, 판정·점유·만료·페이드 설정, 지속 음악 일시 정지와 모듈별 중요도 옵션을 추가했습니다.
- 레이드 루팅 자동 포기에 `형상·도안 등 자동 포기 제외` 옵션과 도안, 장난감, 탈것, 전투 애완동물, 세트가 아닌 단일 형상 해금 아이템, 하우징 장식 및 퀘스트 아이템별 선택을 추가했습니다. 미수집 장비 형상과 앙상블·무기고는 자동 포기 대상에 포함됩니다.
- 주요 팝업 창과 파티 찾기 필터를 메인 툴킷의 중성 팔레트로 통일하고, 과한 청록색 면을 줄였으며, 공격대 그룹 관리 창이 메인 설정 창보다 위에 표시되도록 변경했습니다.
- 순차 사운드 재생에서 앞선 소리가 재생되는 동안 뒤 알림이 만료되어 한 개만 들리던 문제를 수정했습니다.
- 공격대 파티 툴팁에 공대원 행, 빈 자리, 직업 아이콘, 직업별 인원, 방어구별 인원 및 0명 방어구 표시 옵션을 각각 추가했습니다.
- 파티 신청 알림은 인원 도형이 양쪽에서 번갈아 합류하고, 파티 구인 완료 알림은 전원이 안착한 뒤 중앙에서 잔광이 퍼지도록 서로 다른 잔잔한 모션으로 개편했습니다. 반복 모션 미리보기와 모션 ON/OFF, 크기·글꼴·세부 색상 옵션도 추가했습니다.
- 내구도 부족 경고를 같은 HUD 톤의 연속 그라데이션과 빈 경고 마름모 디자인으로 개편하고 경고 깜빡임 ON/OFF·주기, 크기, 글꼴 및 세부 색상 옵션을 추가했습니다.
- 블러드가 새로 시작될 때 짙은 진홍색 의식 배경 위에서 붉은 보석 봉인이 맥동하고, 고금색 문양이 좌우로 펼쳐지며 하단 보석과 잔불이 이어지는 `BLOODLUST` 시작 HUD를 한 번 재생하도록 추가했습니다. 별도 편집 앵커, 미리보기, 모션·문구·위치·세부 색상 옵션도 제공합니다.
- 블러드 시작 HUD의 기본색을 더 짙은 검붉은 암부, 어두운 황동 문양, 선명한 혈색 봉인과 잔불로 조정하고 밝은 선의 백색 혼합을 줄여 게임 화면에서 금색이 베이지색으로 뜨지 않도록 개선했습니다.
- 블러드 시작 HUD에 독립 회전하는 분절 링, 툴킷 전용 중앙 문장, 자홍·검정 시스템 패널과 상태 노드가 조립·고정·맥동·소멸하는 **시스템 기동** 디자인을 추가했습니다. 중앙 문장을 피의 욕망을 오마주한 독자적인 전투 가면으로 발전시키고 골격과 혈색 핵을 따로 조절하도록 시스템 전용 색상 옵션을 8종으로 확장했습니다.
- 공격대 파티 툴팁을 파티 찾기 공격대 목록까지 확장하고, 별도 표시 토글과 기존 직업 아이콘·직업별 인원·방어구별 인원·0명 표시 옵션을 함께 적용했습니다.
- 파티 찾기 필터에서 던전 및 파티 구성 조건을 바꾸면 현재 결과를 즉시 갱신하고, 블러드 적합도를 `BL`/`BL+`/`BL-`로 표시하며, 점수·던전 정렬이 실제 행 순서를 바꾸도록 개편했습니다. Blizzard 제한 상태에서는 기본 순서를 유지합니다.
- 쐐기 도우미의 던전 순간이동 오버레이를 보안 주문 버튼으로 변경하고 WoW 12.1의 재사용 대기시간 및 전투 상태 처리를 안정화했습니다.

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
