# DDingUI Changelog

---

## v1.2.10

_Release date: 2026-06-13_
_Scope: Git changes from commit cf9fc64 (v1.2.9 release) through this release._

### English Patch Notes
- Stabilized custom buff, timed-aura, racial, item, potion, healthstone, and trinket icons so active effects keep duration swipes, textures, cooldown state, glow state, and text settings through combat refreshes.
- Restored reliable custom aura profile initialization and live-aura linking for copied or newly created profiles.
- Reduced custom icon refresh pressure by debouncing layout rebuilds, filtering icon updates by type, caching cooldown target counts, and avoiding unnecessary full rescans during combat.
- Improved CDM group rendering performance by skipping unchanged group layouts, limiting dynamic aura bridge scans, and avoiding repeated frame reconciliation after stable updates.
- Registered spell, item, and duplicate-aura watcher events only while tracked entries exist, reducing idle runtime work.
- Reduced tracked buff bar work by merging duplicate UNIT_AURA and duration updates, trimming startup refreshes, and stopping the tracker when no entries are active.
- Reduced tracked buff duration text overhead by caching aura expiration times during tracker updates and using that cached state for bar, icon, ring, and text refresh ticks before falling back to aura duration queries.
- Removed redundant fallback viewer polling and per-icon glow/desaturation polling that could contribute to stutter or glow flicker.
- Debounced custom icon reloads, icon customization rehooks, and viewer transition recovery so talent changes, loading screens, PvP transitions, and zone changes do not stack repeated full refresh passes.
- Routed timed-aura layout changes through the existing icon update queue and removed duplicate managed-text retry timers.
- Narrowed inactive viewer fallback listeners and player aura listeners, and skipped idle buff tracker startup work when no tracked entries exist.
- Reduced tracked buff bar startup, loading-screen, and specialization-change work to tokenized settle/backstop refreshes instead of multiple delayed full passes.
- Replaced startup default-viewer hiding OnUpdate polling with a small number of scheduled hide passes.
- Debounced group transition refreshes after edit-mode exit and specialization changes to avoid stacking redundant full group renders.
- Coalesced dynamic icon cache-load retries into one pending queue and reduced startup aura suppression rechecks to a single cancelable follow-up scan.
- Indexed timed-aura spellcast targets and player-aura scan targets so frequent combat events avoid repeated full custom icon database walks.
- Registered custom icon aura, spellcast, glow, and death events only while matching tracked icons exist, reducing idle combat event traffic.
- Registered tracked buff bar aura, spellcast, and combat events only when active tracked entries need them, reducing idle event traffic.
- Stopped the tracked buff bar expiration ticker unless manual tracked entries need expiration checks.
- Kept the tracked buff bar expiration ticker stopped until a manual tracked stack actually has an expiration time, reducing idle timer work for manual tracking profiles.
- Preserved concurrent custom icon update filters instead of promoting mixed event batches to full icon refreshes.
- Coalesced GroupSystem hook refresh callbacks into one deferred full group render per frame.
- Deferred dynamic bridge layout hashing until the scheduled refresh executes, avoiding repeated source/icon scans during notification bursts.
- Throttled dynamic bridge aura-hide scans so combat aura bursts are merged before scanning CDM buff frames.
- Coalesced dynamic bridge buff-frame suppression scans from viewer layout hooks and aura events into one pending pass, reducing repeated pool scans during layout bursts.
- Limited dynamic bridge refreshes to source-linked groups when only specific custom icon sources changed, avoiding unnecessary full GroupSystem renders during combat icon state changes.
- Reused the latest CDM group classification for source-targeted dynamic icon refreshes, avoiding another full classification pass when only custom icon state changed.
- Passed changed custom icon keys into dynamic bridge refreshes so source-targeted updates can hash only affected sources instead of rescanning every linked custom icon source.
- Stopped combat-start CDM frame-controller rescans and skipped viewer transition recovery when PvP or zone events did not actually change viewer state, reducing pull and instance-transition stutter.
- Coalesced resource bar specialization, talent, and trait refresh bursts and removed the redundant player power update listener, reducing duplicate resource bar work during combat and transition events.
- Tokenized icon viewer transition refresh timers so repeated specialization, loading-screen, and world-entry events cancel stale delayed refresh batches instead of stacking viewer rescans and reanchors.
- Coalesced assisted highlight and keybind refresh bursts into one dispatch pass, reducing repeated full viewer scans during talent, spell, action-bar, and layout events.
- Replaced fallback buff-icon centering polling with event-driven queued centering so visible buff icons are not re-collected and resorted continuously during play.
- Coalesced proc-glow reapply work from alert, skin, and viewer-rescan bursts into one pending dispatch pass, reducing timer churn and repeated glow restarts.
- Made shapeshift, vehicle, and override resource-bar settle updates cancel previous pending timers so rapid state changes do not stack duplicate resource refreshes.
- Made soul/metamorphosis secondary resource settle updates cancel previous pending timers so repeated aura changes do not stack duplicate resource refreshes.
- Made secondary resource-bar anchor retry updates cancel stale pending timers when the anchor is restored or the bar is disabled, reducing transition-time refresh bursts.
- Made primary resource-bar anchor retry updates cancel stale pending timers when the anchor is restored or the bar is disabled, reducing transition-time refresh bursts.
- Coalesced resource-bar viewer show/hide and loading/level transition refreshes so stale delayed bar updates are canceled during transition bursts.
- Replaced tracked buff bar queued refresh timers with a reusable dispatch frame, reducing timer churn during aura, combat, and manual-stack event bursts.
- Filtered custom aura UNIT_AURA refreshes through cached spell and aura instance targets, then queued only the affected icon keys when possible so unrelated combat aura changes no longer trigger broad custom icon rescans.
- Debounced icon customization ready-glow event handling so cooldown, charge, aura, and specialization event bursts update hooked icons once through a dispatch frame.
- Coalesced CDM frame-controller dirty marking so repeated hook callbacks keep the existing queued reconcile instead of forcing the next update time back to immediate.
- Removed duplicate BuffIcon and pool refresh scheduling from frame-controller hook paths while keeping state tracking and recovery hooks intact.
- Limited proxy anchor synchronization and keybind text updates to event-driven refresh windows instead of continuous per-frame polling.
- Cleaned up options-panel runtime work when the settings window closes, including dynamic icon refresh pollers, add popups, drag ghosts, and tooltips.
- Hardened CDM rendering against protected or secret values, including safer numeric conversion and managed icon state checks.
- Moved custom icon update bursts from per-burst timers to a reusable dispatch frame, reducing timer churn during combat icon events.
- Moved dynamic icon bridge refresh debounce from per-burst timers to a reusable dispatch frame while preserving source-targeted group updates.
- Reused a single dispatch frame for dynamic icon aura-hide scans so repeated player aura bursts do not create new scan timers.
- Coalesced buff bar viewer refreshes from bar-content hooks and player aura events through one reusable dispatch frame.

### Korean Patch Notes
- 버프바 뷰어의 바 콘텐츠 hook과 플레이어 오라 이벤트에서 들어오는 refresh를 하나의 재사용 dispatch 프레임으로 합쳐 중복 타이머 생성을 줄였습니다.
- 플레이어 오라 이벤트가 반복될 때 동적 아이콘 aura-hide 스캔이 새 타이머를 계속 만들지 않도록 단일 dispatch 프레임을 재사용하게 했습니다.
- 동적 아이콘 브리지 갱신 디바운스를 매번 새 타이머로 예약하지 않고 재사용 dispatch 프레임으로 처리하면서, 변경된 source 그룹만 갱신하는 경로는 유지했습니다.
- 커스텀 아이콘 갱신 burst를 매번 새 타이머로 예약하지 않고 재사용 dispatch 프레임으로 처리해 전투 중 아이콘 이벤트의 타이머 생성 부담을 줄였습니다.
- 지원 강조와 단축키 텍스트 갱신을 한 번의 디스패치 처리로 합쳐 특성, 주문, 액션바, 레이아웃 이벤트가 몰릴 때 전체 뷰어 재스캔이 반복되지 않도록 줄였습니다.
- 강화효과 아이콘 중앙 정렬 fallback을 상시 폴링 대신 이벤트 기반 큐 처리로 바꿔, 플레이 중 보이는 강화효과 아이콘을 계속 재수집하고 재정렬하지 않도록 줄였습니다.
- 발동 글로우 재적용 작업을 알림, 스킨, 뷰어 재스캔 이벤트마다 타이머로 쌓지 않고 한 번의 pending 디스패치로 합쳐 타이머 생성과 반복 글로우 재시작을 줄였습니다.
- 변신, 차량, 오버라이드 상태 전환 중 리소스 바 settle 갱신이 반복될 때 이전 대기 타이머를 취소하도록 바꿔 중복 리소스 갱신이 쌓이지 않게 했습니다.
- 영혼 조각/탈태 보조 자원 settle 갱신도 이전 대기 타이머를 취소하도록 바꿔 반복 오라 변경 중 중복 갱신이 쌓이지 않게 했습니다.
- 보조 자원바 앵커 재시도 갱신이 앵커 복구나 바 비활성화 시 남은 대기 타이머를 취소하도록 바꿔 전환 구간의 갱신 burst를 줄였습니다.
- 주 자원바 앵커 재시도 갱신도 앵커 복구나 바 비활성화 시 남은 대기 타이머를 취소하도록 바꿔 전환 구간의 갱신 burst를 줄였습니다.
- 리소스바의 뷰어 표시/숨김과 로딩/레벨 전환 후속 갱신을 합쳐 전환 burst 중 오래된 지연 바 갱신이 남아 실행되지 않게 했습니다.
- 추적 버프 바의 큐 갱신 타이머를 재사용 dispatch 프레임으로 바꿔 오라, 전투, 수동 스택 이벤트가 몰릴 때 타이머 생성 부담을 줄였습니다.
- 전투 시작만으로 CDM 프레임 컨트롤러가 전체 재스캔을 돌리지 않게 하고, PvP/지역 이벤트에서 실제 뷰어 상태 변화가 없으면 전환 복구를 건너뛰어 전투 시작과 인스턴스 전환 시 스터터링을 줄였습니다.
- 리소스 바의 전문화, 특성, trait 갱신 burst를 한 번으로 합치고 중복 플레이어 파워 갱신 리스너를 제거해 전투와 전환 이벤트 중 리소스 바 중복 작업을 줄였습니다.
- 아이콘 뷰어 전환 갱신 타이머를 토큰 기반으로 바꿔 전문화, 로딩 화면, 월드 진입 이벤트가 반복될 때 오래된 지연 갱신 묶음이 뷰어 재스캔과 재고정을 누적 실행하지 않게 했습니다.
- 커스텀 오라 UNIT_AURA 갱신을 캐시된 주문/오라 인스턴스 대상 기준으로 걸러, 가능한 경우 영향받은 아이콘 키만 갱신하게 해서 무관한 전투 오라 변화가 커스텀 아이콘 전체 재스캔으로 이어지지 않게 했습니다.
- 동적 브리지의 버프 프레임 억제 스캔을 viewer 레이아웃 hook과 오라 이벤트에서 하나의 pending pass로 병합해 레이아웃 burst 중 반복 pool 스캔을 줄였습니다.
- 특정 커스텀 아이콘 source만 바뀐 경우 동적 브리지 갱신을 해당 source에 연결된 그룹으로 제한해, 전투 중 아이콘 상태 변화가 불필요한 전체 GroupSystem 렌더로 번지지 않게 했습니다.
- 커스텀 아이콘 상태만 바뀐 source 대상 갱신에서는 최신 CDM 그룹 분류 캐시를 재사용해, 불필요한 전체 분류 패스를 한 번 더 수행하지 않게 했습니다.
- 변경된 커스텀 아이콘 키를 동적 브리지 갱신에 전달해 source 대상 갱신이 모든 연결 source를 다시 스캔하지 않고 영향받은 source만 hash 계산하도록 줄였습니다.
- 추적 중인 버프 바, 아이콘, 원형, 텍스트의 지속시간 갱신이 오라 만료 시간 캐시를 먼저 사용하도록 개선해 전투 중 반복 오라 조회와 텍스트 갱신 부담을 줄였습니다.
- 아이콘 커스터마이징 준비 글로우 이벤트 처리를 디바운스해 쿨다운, 충전, 오라, 전문화 이벤트가 몰릴 때 훅된 아이콘을 디스패치 프레임에서 한 번만 갱신하도록 했습니다.
- CDM 프레임 컨트롤러 dirty 표시를 병합해 반복 hook 콜백이 기존 예약된 재조정을 유지하고 다음 갱신 시간을 계속 즉시로 되돌리지 않도록 했습니다.
- 프레임 컨트롤러 hook 경로에서 중복 BuffIcon 및 pool refresh 예약을 제거하되 상태 추적과 복구 hook은 유지했습니다.
- 활성 추적 항목이 필요로 할 때만 추적 버프 바의 오라, 주문 시전, 전투 이벤트를 등록해 대기 중 이벤트 유입을 줄였습니다.
- 수동 추적 항목의 만료 체크가 필요할 때만 추적 버프 바 만료 ticker를 켜도록 줄였습니다.
- 수동 추적 프로필에서도 실제 만료 시간이 잡힌 스택이 있을 때만 추적 버프 바 만료 ticker를 유지해 idle timer 작업을 줄였습니다.
- 동시에 들어온 커스텀 아이콘 갱신 필터를 보존해 혼합 이벤트가 불필요한 전체 아이콘 갱신으로 커지지 않게 했습니다.
- GroupSystem HookEngine 갱신 콜백을 한 프레임에 한 번의 전체 그룹 렌더로 병합했습니다.
- 동적 브리지 레이아웃 해시 계산을 예약된 갱신 실행 시점으로 미뤄 알림이 몰릴 때 source/icon 스캔이 반복되지 않게 했습니다.
- 동적 브리지 오라 숨김 스캔을 throttle 처리해 전투 중 오라 이벤트가 몰릴 때 CDM 버프 프레임 스캔을 병합했습니다.
- 커스텀 버프, 지속시간 오라, 종족 특성, 사용 아이템, 물약, 생명석, 장신구 아이콘이 전투 중 갱신 후에도 지속시간 스와이프, 텍스처, 쿨다운 상태, 글로우 상태, 텍스트 설정을 유지하도록 안정화했습니다.
- 복사한 프로필이나 새로 만든 프로필에서도 커스텀 오라 초기화와 실제 오라 연결이 정상적으로 동작하도록 개선했습니다.
- 레이아웃 재구성 디바운스, 아이콘 유형별 갱신 필터, 쿨다운 대상 수 캐시, 전투 중 불필요한 전체 재스캔 회피로 커스텀 아이콘 갱신 부담을 줄였습니다.
- 변경 없는 그룹 레이아웃을 건너뛰고, 동적 오라 브리지 스캔을 제한하며, 안정 상태 이후 반복 프레임 재조정을 멈춰 CDM 그룹 렌더링 성능을 개선했습니다.
- 추적 대상이 있을 때만 주문, 아이템, 중복 오라 watcher 이벤트를 등록해 대기 상태의 런타임 작업을 줄였습니다.
- 중복 UNIT_AURA와 지속시간 갱신을 병합하고, 시작 시 불필요한 갱신을 줄이며, 추적 항목이 없으면 트래커를 멈추도록 추적 버프 바 작업량을 줄였습니다.
- 스터터나 글로우 깜빡임을 유발할 수 있는 fallback 뷰어 폴링과 아이콘별 글로우/비활성화 폴링을 제거했습니다.
- 커스텀 아이콘 재로드, 아이콘 커스터마이징 재훅, 뷰어 전환 복구를 디바운스해 특성 변경, 로딩 화면, PvP 전환, 지역 변경 때 반복 전체 갱신이 겹치지 않게 했습니다.
- 지속시간 오라의 레이아웃 변경을 기존 아이콘 갱신 큐로 통합하고, 관리 아이콘 텍스트 재시도 타이머 중복을 제거했습니다.
- 비활성 뷰어 fallback 리스너와 플레이어 오라 리스너 범위를 줄이고, 추적 항목이 없을 때는 버프 트래커 시작 작업을 건너뛰도록 했습니다.
- 추적 버프 바의 시작, 로딩 화면, 전문화 변경 작업을 여러 지연 전체 갱신 대신 토큰 기반 settle/backstop 갱신으로 줄였습니다.
- 시작 시 기본 뷰어 숨김 처리를 매 프레임 OnUpdate 폴링 대신 소수의 예약 패스로 교체했습니다.
- 편집모드 종료와 전문화 변경 뒤 그룹 전환 갱신을 디바운스해 불필요한 전체 그룹 렌더링이 겹치지 않게 했습니다.
- 동적 아이콘 캐시 로드 재시도를 하나의 pending 큐로 합치고, 시작 시 오라 억제 재확인을 취소 가능한 후속 스캔 1회로 줄였습니다.
- 지속시간 오라 주문 시전 대상과 플레이어 오라 스캔 대상을 인덱싱해 잦은 전투 이벤트에서 커스텀 아이콘 DB 전체 순회를 반복하지 않도록 했습니다.
- 일치하는 추적 아이콘이 있을 때만 커스텀 아이콘 오라, 주문 시전, 글로우, 사망 이벤트를 등록해 대기 중 전투 이벤트 유입을 줄였습니다.
- 프록시 앵커 동기화와 키바인드 텍스트 갱신을 지속적인 매 프레임 폴링 대신 이벤트 기반 갱신 구간에서만 실행하도록 제한했습니다.
- 설정창이 닫힐 때 동적 아이콘 갱신 poller, 추가 팝업, 드래그 고스트, 툴팁 같은 옵션 패널 임시 작업을 정리하도록 개선했습니다.
- 보호 값이나 secret 값이 섞인 상황에서도 CDM 렌더링이 깨지지 않도록 숫자 변환과 관리 아이콘 상태 확인을 더 안전하게 처리했습니다.

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
