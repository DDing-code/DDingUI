# DDingUI Toolkit Changelog

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
