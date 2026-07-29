# DDingUI Changelog

---

## v1.3.1.1

_Release date: 2026-07-29_
_Scope: Git changes from v1.3.1 through this release._

### English Patch Notes
- Added a per-icon consumable option that hides the icon when none of the configured items are available, while keeping it visible in edit mode and updating the CDM layout when inventory counts change.

### Korean Patch Notes
- 설정된 소모품을 보유하지 않았을 때 해당 아이콘을 숨기는 개별 옵션을 추가했습니다. 편집모드에서는 아이콘을 계속 표시하며, 재고 수량이 바뀌면 CDM 레이아웃에 즉시 반영됩니다.

---

## v1.3.1

_Release date: 2026-07-29_
_Scope: Git changes from v1.2.14 through this release._

### English Patch Notes
- Reworked the CDM settings workflow with section-based navigation, pinned live previews, separate skill and buff catalogs, clearer add controls, per-icon detail settings, and streamlined group and icon context actions.
- Expanded CDM group management with mixed skill and buff assignment, movement between native and custom groups, group rename and delete actions, inactive-state controls, and more consistent legacy-group behavior.
- Added conditional custom aura actions that can recolor or glow a tracker, icon, or group from another tracked effect, while fixing grouped tracker rendering, stack-based bars, child ordering, and edit-mode bounds.
- Improved item, potion, trinket, and racial effect visuals with active overlays, aura and proc glows, racial buff variants, stable glow persistence, inherited thickness, and restored action-button glow behavior.
- Fixed assigned buffs and custom icons losing active state, duration, position, or ownership after combat, talent changes, specialization changes, group moves, and deferred layout updates.
- Prevented timeless effects from repeatedly refreshing cooldown swipes and reduced stale aura, hidden trigger, inactive placeholder, and reused-frame visual artifacts.
- Reduced gameplay overhead by consolidating CustomIcons and GroupSystem work into dirty queues, coalescing structural and trinket updates, suspending inactive event handlers, caching classification, and stopping hidden Options refresh work.
- Split large runtime and Options modules into focused components while preserving existing profiles, icon assignments, and SavedVariables compatibility.
- Improved tracked bars with anchor and offset controls, reliable restoration of the default viewer when disabled, stack support, persistent ordering, clearer width behavior, and completed Korean terminology and translations.

### Korean Patch Notes
- CDM 설정 화면을 섹션형 탐색, 상단 고정 실시간 미리보기, 스킬·강화효과 카탈로그 분리, 명확한 추가 버튼, 아이콘별 상세 설정, 간소화된 그룹·아이콘 메뉴 구조로 개편했습니다.
- 기본 그룹과 커스텀 그룹 사이의 스킬·강화효과 혼합 할당 및 이동, 그룹 이름 변경·삭제, 비활성 상태 표시 설정을 추가하고 이전 버전 그룹의 동작을 통일했습니다.
- 다른 추적 효과의 상태에 따라 특정 추적기·아이콘·그룹의 색상이나 글로우를 변경하는 커스텀 오라 조건 동작을 추가하고, 그룹 렌더링·중첩 바·하위 항목 순서·편집모드 영역을 수정했습니다.
- 아이템·물약·장신구·종족 특성에 활성 효과 오버레이와 오라·발동 글로우를 추가하고, 종족별 버프 변형 감지, 글로우 유지, 두께 상속, 액션 버튼 글로우를 안정화했습니다.
- 전투, 특성·전문화 변경, 그룹 이동, 지연된 레이아웃 갱신 후 할당된 강화효과와 커스텀 아이콘의 활성 상태·지속시간·위치·소유권이 사라지거나 어긋나는 문제를 수정했습니다.
- 지속시간이 무한인 효과의 스와이프가 반복 갱신되는 문제와 오래된 오라 상태, 숨겨진 트리거, 비활성 아이콘, 재사용 프레임에 남는 시각 효과를 수정했습니다.
- CustomIcons와 GroupSystem 갱신을 단일 변경 대기열로 통합하고 구조·장신구 갱신 병합, 비활성 이벤트 중지, 분류 캐시, 닫힌 설정창 작업 중지로 실전 플레이 부하를 줄였습니다.
- 대형 런타임 및 설정 모듈을 역할별 파일로 분리하면서 기존 프로필, 아이콘 할당, SavedVariables 호환성을 유지했습니다.
- 추적중인 막대에 앵커·오프셋 설정, 비활성화 시 기본 뷰어 복원, 중첩 표시, 순서 저장을 보강하고 너비 동작 설명과 한국어 용어·번역을 정리했습니다.

---

## v1.2.14

_Release date: 2026-07-25_
_Scope: Git changes from v1.2.13 through this release._

### English Patch Notes
- Fixed buff-group recovery after talent and specialization changes so active buffs remain in layout, inactive entries stay excluded, and reused frames no longer retain stale position or visual state.
- Rebuilt changed buff frames and normalized specialization icon snapshots so returning or newly available effects rejoin the intended order instead of appearing centered, overlapping, or missing until reload.
- Reduced specialization profile storage by sharing a base snapshot and saving per-specialization differences, while retaining automatic compatibility with existing SavedVariables.
- Reduced repeated runtime work by coalescing same-frame custom icon, dynamic group, resource bar, and tracked buff updates and avoiding redundant full refresh chains.
- Moved the custom icon editor and Options-only localization to the LoadOnDemand settings addon, reducing code and translation data loaded during normal gameplay.
- Consolidated repeated Options controls and removed an unused embedded library to reduce maintenance and startup overhead without changing existing settings.

### Korean Patch Notes
- 특성 및 전문화 변경 후 강화효과 그룹을 복구할 때 활성 강화효과는 레이아웃에 유지하고 비활성 항목은 제외하며, 재사용 프레임에 이전 위치나 시각 상태가 남지 않도록 수정했습니다.
- 변경된 강화효과 프레임을 다시 구성하고 전문화별 아이콘 스냅샷을 정리해 돌아오거나 새로 활성화된 효과가 중앙에 겹치거나 누락되지 않고 의도한 순서에 합류하도록 개선했습니다.
- 공통 기본 스냅샷과 전문화별 차이만 저장하도록 전문화 프로필 저장 구조를 압축했으며, 기존 SavedVariables는 자동 호환되도록 유지했습니다.
- 같은 프레임에 발생하는 커스텀 아이콘, 동적 그룹, 자원 바, 추적중인 막대 갱신을 합치고 중복 전체 갱신 연쇄를 줄여 런타임 부담을 낮췄습니다.
- 커스텀 아이콘 편집기와 Options 전용 번역을 LoadOnDemand 설정 애드온으로 이동해 일반 플레이 중 로드되는 코드와 번역 데이터를 줄였습니다.
- 반복되는 Options 컨트롤을 통합하고 사용하지 않는 내장 라이브러리를 제거해 기존 설정 동작을 유지하면서 시작 및 유지보수 부담을 줄였습니다.

---

## v1.2.13

_Release date: 2026-07-19_
_Scope: Git changes from v1.2.12 through this release._

### English Patch Notes
- Stabilized CDM buff collection and layout after specialization, talent, and spell-list changes so rebuilt or reused icons rejoin their group instead of remaining centered, overlapping, or missing until reload.
- Preserved returning spell order and invalidated stale layout slots when the active buff list changes, while smoothing custom aura progress and cooldown swipe updates.
- Improved tracked buff bars with display-rate progress, persistent edit-mode anchors and drag positions, and stable placement through activation, combat, and reloads.
- Added inactive buff placeholders with gray icon rendering, and limited the buff catalog to current CDM entries while filtering hidden or unavailable effects.
- Added event-driven trinket effect tracking with resolved effect icons, slot-icon duration display, and per-icon glow controls without forcing automatic proc glow.
- Simplified icon context menus by consolidating customization and glow controls and removing unsupported or duplicate menu paths.

### Korean Patch Notes
- 전문화, 특성, 주문 목록 변경 후 재생성되거나 재사용된 CDM 강화효과가 그룹에서 빠져 중앙에 남거나 겹치거나 재접속 전까지 사라지는 문제를 수정했습니다.
- 활성 강화효과 목록이 바뀔 때 돌아온 주문의 순서를 유지하고 오래된 레이아웃 슬롯을 초기화했으며, 커스텀 오라 진행률과 쿨다운 스와이프 갱신을 부드럽게 개선했습니다.
- 추적중인 버프 바의 진행률을 화면 갱신 주기에 맞추고, 편집모드 앵커와 드래그 위치가 활성화, 전투, 리로드 후에도 유지되도록 안정화했습니다.
- 비활성 강화효과를 회색으로 표시하는 자리표시 아이콘을 추가하고, 숨겨졌거나 사용할 수 없는 효과를 제외해 현재 CDM 항목만 강화효과 카탈로그에 표시하도록 정리했습니다.
- 이벤트 기반 장신구 효과 추적, 효과 아이콘 판별, 장신구 슬롯 아이콘의 지속시간 표시와 아이콘별 글로우 옵션을 추가했으며 자동 발동 글로우는 강제하지 않도록 했습니다.
- 아이콘 커스터마이징과 글로우 설정을 우클릭 메뉴에 통합하고 지원하지 않거나 중복된 메뉴 경로를 정리했습니다.

---

## v1.2.12

_Release date: 2026-07-02_
_Scope: Git changes from v1.2.11 through this release._

### English Patch Notes
- Improved CDM buff and custom group layout recovery after specialization, talent, and spell-list changes so newly restored icons no longer keep stale center positions until reload.
- Stabilized custom icon rendering for inactive, hidden-active, racial, managed, and cooldown states so grayscale, text placement, glow state, and cooldown visuals remain consistent through refreshes.
- Improved custom group previews and icon motion so runtime groups and settings previews react more consistently to layout changes.
- Added support for showing inactive custom buff icons as gray icons when the group option is enabled.
- Reduced tracked buff bar movement and duration update overhead by queuing updates, throttling duration polling, and merging duplicate startup/spec refreshes.
- Reduced CDM refresh pressure by queuing repeated group refreshes, narrowing dynamic group updates, skipping unnecessary style passes, reusing dispatch frames, and trimming redundant recovery timers.
- Cleaned up unloaded runtime option, backup, and embedded library sources to reduce addon load and maintenance overhead.

### Korean Patch Notes
- 전문화, 특성, 주문 목록 변경 후 CDM 강화효과와 커스텀 그룹 레이아웃이 복구될 때 새로 돌아온 아이콘이 /reload 전까지 중앙 위치에 남는 문제를 개선했습니다.
- 비활성, 지속 효과 숨김, 종족 특성, 관리 아이콘, 쿨다운 상태의 커스텀 아이콘 렌더링을 안정화해 회색 처리, 텍스트 위치, 글로우 상태, 쿨다운 표시가 갱신 중에도 일관되게 유지되도록 했습니다.
- 커스텀 그룹 미리보기와 아이콘 이동 애니메이션이 레이아웃 변경을 더 일관되게 반영하도록 개선했습니다.
- 그룹 옵션이 켜져 있을 때 비활성 커스텀 강화효과를 회색 아이콘으로 표시하는 기능을 추가했습니다.
- 추적중인 버프 바의 위치 변경과 지속시간 갱신 부담을 줄이기 위해 업데이트를 대기열로 합치고, 지속시간 폴링과 시작/전문화 갱신 중복을 줄였습니다.
- 반복 그룹 갱신 대기열, 동적 그룹 부분 갱신, 불필요한 스타일 패스 생략, dispatch 프레임 재사용, 중복 복구 타이머 축소로 CDM 갱신 부담을 줄였습니다.
- 로드되지 않는 옵션 런타임, 백업, 내장 라이브러리 소스를 정리해 애드온 로드와 유지보수 부담을 줄였습니다.

---

## v1.2.11

_Release date: 2026-06-18_
_Scope: Git changes from v1.2.10 through this release._

### English Patch Notes
- Reduced combat-time refresh pressure by routing custom icon, dynamic icon, resource bar, and buff tracker updates through narrower queued refresh paths.
- Reduced unnecessary full scans and layout rebuilds by filtering cooldown, aura, item, spell, and viewer transition events before they reach CDM group rendering.
- Improved custom aura and timed aura stability so active icon, duration, text, glow, and cooldown updates are targeted to the changed sources instead of broad rescans.
- Restored stable flight and hidden-state fade behavior so alpha changes are not stacked or replayed during layout and icon refreshes.
- Fixed buff-group wrapping so multi-row buff layouts stay pinned to the correct edge for the selected wrap direction.
- Hardened frame picker and options refresh paths against missing config callbacks.
- Updated TOC interface metadata for the current game client patch.

### Korean Patch Notes
- 커스텀 아이콘, 동적 아이콘, 자원 바, 버프 추적 갱신을 더 좁은 대기열 경로로 보내 전투 중 갱신 부담을 줄였습니다.
- 쿨다운, 오라, 아이템, 주문, 뷰어 전환 이벤트를 CDM 그룹 렌더링 전에 필터링해 불필요한 전체 스캔과 레이아웃 재구성을 줄였습니다.
- 커스텀 오라와 시간제 오라가 활성 아이콘, 지속시간, 텍스트, 글로우, 쿨다운 갱신을 변경된 대상에만 적용하도록 안정성을 높였습니다.
- 비행 및 숨김 상태 페이드가 레이아웃/아이콘 갱신 중 중첩되거나 반복 재생되지 않도록 안정적인 동작을 복원했습니다.
- 강화효과 그룹이 여러 줄로 줄바꿈될 때 선택한 줄바꿈 방향에 맞는 기준 edge에 고정되도록 수정했습니다.
- 프레임 선택기와 설정창 갱신 경로에서 설정 콜백이 없을 때 오류가 나지 않도록 보강했습니다.
- 현재 게임 클라이언트 패치에 맞춰 TOC 인터페이스 메타데이터를 갱신했습니다.

---

## v1.2.10

_Release date: 2026-06-05_
_Scope: Git changes from v1.2.9 through this release._

### English Patch Notes
- Stabilized custom buff and timed-aura icons so active effects keep their duration swipe, texture, glow state, and text settings through combat refreshes.
- Improved custom item, potion, healthstone, trinket, and racial cooldown refreshes so item fast-path updates no longer skip related aura or spell cooldown updates.
- Reduced custom icon refresh pressure by debouncing layout rebuilds, filtering icon updates by type, and avoiding unnecessary full rescans during combat.
- Improved CDM group recovery for profile changes and source-group initialization so copied or newly created profiles retain usable source groups.
- Hardened CDM rendering against protected or secret values, including safer numeric conversion and managed icon state checks.
- Improved tracked buff bar performance by registering events only while the feature is active, merging duplicate updates, and cleaning startup timers when disabled.
- Cleaned up options-panel runtime work when the settings window closes, including dynamic icon refresh pollers, add popups, drag ghosts, and tooltips.
- Reduced aura glow flicker by preserving recent glow state briefly while managed icons are refreshing.

### Korean Patch Notes
- 커스텀 강화효과와 시간제 오라 아이콘이 전투 중 갱신되어도 지속시간 스와이프, 텍스처, 글로우 상태, 텍스트 설정을 유지하도록 안정화했습니다.
- 커스텀 사용 아이템, 물약, 생명석, 장신구, 종족 특성 쿨다운 갱신을 개선해 item 빠른 갱신 경로가 관련 오라나 주문 쿨다운 갱신을 건너뛰지 않도록 했습니다.
- 레이아웃 재구성 디바운스, 아이콘 타입별 갱신 필터, 전투 중 불필요한 전체 재스캔 회피로 커스텀 아이콘 갱신 부담을 줄였습니다.
- 프로필 변경과 소스 그룹 초기화 시 CDM 그룹 복구를 개선해 복사되거나 새로 만든 프로필에서도 사용할 수 있는 소스 그룹이 유지되도록 했습니다.
- 보호된 값이나 secret 값이 섞인 상황에서도 CDM 렌더링이 깨지지 않도록 숫자 변환과 관리 아이콘 상태 확인을 더 안전하게 처리했습니다.
- 추적중인 버프 바가 활성화된 동안에만 이벤트를 등록하고, 중복 업데이트를 합치며, 비활성화 시 시작 타이머를 정리하도록 성능을 개선했습니다.
- 설정창을 닫을 때 동적 아이콘 갱신 poller, 추가 팝업, 드래그 고스트, 툴팁 같은 옵션 패널 런타임 작업을 정리하도록 했습니다.
- 관리 아이콘 갱신 중 최근 글로우 상태를 짧게 보존해 오라 글로우 깜빡임을 줄였습니다.

---

## v1.2.9

_Release date: 2026-05-26_
_Scope: Git changes from v1.2.8 through this release._

### English Patch Notes
- Added cast bar channel tick markers and timing indicators for supported spells.
- Improved CDM spell management so restored, preset, and newly learned spells keep their intended order across rescans and talent changes.
- Stabilized custom buff shortcuts, preset icons, and unassigned buff handling so duplicate, question-mark, or incorrectly listed buff icons are avoided.
- Improved Bloodlust/Heroism-style and Time Spiral-style timed buff tracking, including debuff seeding, icon texture selection, active-state linking, and combat persistence.
- Fixed custom buff rendering in CDM groups, including grouped text option inheritance, hidden-source suppression, duplicate buff filtering, expired aura cleanup, and stale transparency states.
- Reworked custom item and trinket cooldown tracking around targeted item/slot watchers so healthstones, potions, PvP trinkets, equipped trinkets, and slot icons update without full custom icon churn.
- Improved PvP and instance transition recovery so CDM viewers keep order, visibility, alpha, and cooldown state when entering or leaving instances.
- Reduced custom icon runtime pressure by removing stale cache paths and trimming local declarations that could trigger Lua local-variable warnings.
- Added shared UI motion helpers for smoother options-panel and button feedback.

### Korean Patch Notes
- 지원 주문의 시전바 채널 틱 표시와 타이밍 표시를 추가했습니다.
- CDM 스펠 관리 안정성을 개선해 복원된 스펠, 프리셋 스펠, 새로 배운 스펠이 재스캔과 특성 변경 후에도 의도한 순서를 유지하도록 했습니다.
- 커스텀 강화효과 바로가기, 프리셋 아이콘, 할당되지 않은 강화효과 처리를 안정화해 중복 아이콘, 물음표 아이콘, 잘못 분류된 강화효과가 나오지 않도록 했습니다.
- 피의 욕망 계열 및 시간의 와류 계열 시간제 강화효과 추적을 개선했습니다. 디버프 기반 시드, 아이콘 텍스처 선택, 활성 상태 연결, 전투 중 유지 처리를 보강했습니다.
- CDM 그룹 안의 커스텀 강화효과 렌더링을 수정했습니다. 그룹 텍스트 옵션 상속, 숨김 처리, 중복 필터링, 만료 오라 정리, 오래 남는 투명도 상태를 보정했습니다.
- 커스텀 사용 아이템과 장신구 쿨다운 추적을 item/slot 단위 감시 방식으로 재구성했습니다. 생명석, 물약, PvP 장신구, 장착 장신구, 슬롯 아이콘이 전체 커스텀 아이콘 갱신 없이 필요한 대상만 갱신됩니다.
- PvP 및 인스턴스 입퇴장 후 CDM 뷰어의 순서, 표시 상태, 투명도, 쿨다운 상태가 유지되도록 복구 흐름을 개선했습니다.
- 오래된 캐시 경로와 과도한 local 선언을 줄여 커스텀 아이콘 런타임 부담과 Lua local-variable 경고 가능성을 낮췄습니다.
- 옵션 패널과 버튼 피드백을 더 부드럽게 만드는 공용 UI 모션 헬퍼를 추가했습니다.

---

## v1.2.8

_Scope: Git changes from the v1.2.7.2 development line through this release._

### English Patch Notes
- Reworked the CDM spell management flow: the assigned spell grid now lives at the top of the Layout tab, supports a plus-button add menu, and includes a Blizzard CDM order restore action.
- Improved assigned spell drag and drop behavior, including scaled cursor coordinates, aligned drag ghosts, insert/swap feedback, and safer popup row fonts.
- Added unassigned spell management for buff-category CDM groups, including right-click remove/unassign behavior and a shared unassigned buff spell pool across buff groups.
- Improved combat tracking for trinkets, item cooldowns, dynamic item slots, Bloodlust/Heroism-style effects, exhaustion debuffs, and custom timed buff triggers.
- Stabilized custom buff icons during combat by waking managed icons, keeping timer-driven Bloodlust icons alive, restoring managed buff opacity, and reapplying dynamic icon text settings.
- Improved custom buff/CDM rendering by reparenting custom buff CDM icons, aligning custom buff icon text to group text options, anchoring aura glows on the host frame, and debouncing glow removal.
- Expanded tracked bar support with layout controls, stronger styling persistence, item frame pool collection, and DDingUI mover-mode positioning while keeping Blizzard Edit Mode behavior locked.
- Added buff icon movement animation for appearing/disappearing tracked buffs, with a clearer visual toggle label.
- Stabilized CDM icon order across talent changes so custom/manual additions are not displaced by Blizzard CDM rescans.
- Added safeguards for mover config opening and Assist Highlight updates when group names collide with non-frame globals such as `test`.

### 한국어 패치노트
- CDM 스펠 관리 흐름을 재구성했습니다. 할당된 스펠 그리드는 이제 레이아웃 탭 최상단에 표시되며, 플러스 버튼 추가 메뉴와 블리자드 CDM 기본 순서 복원 기능을 제공합니다.
- 할당 스펠 드래그 앤 드롭을 개선했습니다. 스케일 적용 좌표, 드래그 고스트 위치, 끼워넣기/교체 피드백, 팝업 행 폰트 안정성을 보강했습니다.
- 강화효과 계열 CDM 그룹에 할당되지 않은 스펠 관리 기능을 추가했습니다. 우클릭 삭제/할당 해제와 모든 강화효과 그룹이 공유하는 미할당 버프 풀을 지원합니다.
- 전투 중 장신구, 사용 아이템, 동적 아이템 슬롯, 블러드/영웅심 계열 효과, 탈진 디버프, 커스텀 시간제 버프 트리거 감지를 개선했습니다.
- 전투 중 커스텀 강화효과 아이콘 안정성을 개선했습니다. 관리 중인 아이콘을 깨우고, 타이머 기반 블러드 아이콘을 유지하며, 투명도와 동적 아이콘 텍스트 설정을 다시 적용합니다.
- 커스텀 강화효과/CDM 렌더링을 개선했습니다. 커스텀 강화효과 CDM 아이콘 reparent, 그룹 텍스트 옵션에 맞춘 텍스트 위치, 호스트 프레임 기준 글로우, 글로우 제거 디바운스를 적용했습니다.
- 추적중인 막대 기능을 확장했습니다. 레이아웃 옵션, 스타일 유지, item frame pool 수집, DDingUI 자체 편집모드 이동을 지원하며 Blizzard 편집모드에서는 잠금 동작을 유지합니다.
- 버프 아이콘이 나타나고 사라질 때 움직이는 애니메이션을 추가하고, 시각 효과 토글 이름을 더 명확하게 정리했습니다.
- 특성 변경 시 CDM 아이콘 순서를 안정화하여 커스텀/수동 추가 아이콘이 블리자드 CDM 재스캔에 밀리지 않도록 했습니다.
- 이동 설정 열기와 Assist Highlight 갱신을 방어 처리하여 `test` 같은 그룹명이 비프레임 전역값과 충돌해도 오류가 나지 않게 했습니다.

---

## v1.2.7.1

### Updates
- Improved CDM icon drag reorder feedback: target body swaps icons, target edges insert between icons.
- Refined the hover indicator to show only a swap border or a single insert line.

---

## v1.2.7

### Updates
- Version bump for the DDingUI Cooldown Manager and Options addon.
- Includes the recent CDM group, custom icon, default group item/potion, and assigned icon grid improvements.
- Added a smoother edit mode grid fade with subtle minor lines, accent snap lines, and brighter center guides.

---

## v1.2.6

### 버그 수정 / Bug Fixes
- 전투 중 다이나믹 아이콘(생석, 치물 등)의 크기가 0x0으로 깜빡이는 문제 수정 (메서드 오버라이드를 통해 CustomIcons의 프레임 제어 원천 차단)
- Fixed dynamic icons (Healthstone, Potions, etc.) flickering to 0x0 size during combat (blocked CustomIcons frame control via method overrides)

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
