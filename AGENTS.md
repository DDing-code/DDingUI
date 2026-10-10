# DDingUI canonical knowledge vault

- `F:\wow` is the canonical DDingUI knowledge vault and the first place to search for project information.
- Use the `obsidian` MCP server first when available; it is restricted to `F:\wow`.
- Start with `F:\wow\00 DDingUI Brain.md`, then read the relevant curated notes and generated snapshot.
- The live source remains executable truth. When source and vault differ, verify the source and refresh the vault.
- After changes that create durable project knowledge, update the relevant vault note and run `F:\wow\Refresh-DDingUI-Brain.ps1`.
- Do not put credentials, private logs, or live SavedVariables in the vault.

# DDingUI 프로젝트 규칙

## 파일 위치 (2026-09-30 기준)
- 메인 저장소: C:/Users/D2JK/바탕화면/cd/DDingUI_Super/
- 애드온 경로: G:/wow2/World of Warcraft/_retail_/Interface/AddOns/ — 각 애드온은 Super 루트의 같은 이름 폴더를 가리키는 링크다. AddOns 쪽에 복사본을 만들지 않는다.
- 활성 애드온 (폴더명 · 버전):
  - `DDingUI_CDM` 2.1.6 — 쿨다운 매니저 본체
  - `DDingUI_CDM_Option` 2.1.6 — CDM 옵션
  - `DDingUI_Toolkit` 2.1.8
  - `DDingUI_Profile` 260923.1
  - `DDingUI_RaidHelper` 2.1.0
  - `DDingUI_FX` 0.1.0 — TGA 모션·효과음
  - `DDIngUI_APL` 0.1.2-alpha — 헤키리형 공격 우선순위 (폴더명 `DDIng` 대소문자 그대로)
  - `DDingUI_StyleLib` 1.4.0 (MINOR 7) — 공유 라이브러리 원본 (각 애드온은 `Libs/DDingUI_StyleLib/`에 내장 사본 사용, `Media/` 텍스처 포함)
- **폐기:** `PongPongAura` — 사용자가 2026-09-30 폐기 지시. 소스·AddOns 링크·SavedVariables를 휴지통으로 보냈다. 다시 만들지 않는다.
- 레거시 호환 폴더 (기능 추가 금지): `DDingUI` (CDM Legacy Data Bridge), `DDingUI_Options` (CDM Options Legacy Folder)
- **폐기:** `DDingUI_PersonalBar`, `DDingUI_DF_Plugin` — 사용자가 2026-09-30 폐기 지시. 소스·SavedVariables를 휴지통으로 보냈다. 다시 만들지 않는다.
- **개발 중지:** `DDingUI_UF` — 사용자가 2026-08-26에 개발 중지를 선언했다. 사용자가 다시 지시하기 전에는 수정하지 않는다. 볼트 노트에 UF 확장이 "최근 방향"으로 적혀 있어도 이 결정이 우선한다.
- 빈 폴더였던 `DDingUI_Essential`, `DDingUI_MythicPlus`, `DDingUI_Nameplate`, `DDingUI_Controller`, `DDingUI_Skin_Classic`은 2026-09-30에 폴더와 AddOns 링크를 모두 제거했다.
- **Git 범위 (2026-09-30):** 이 저장소는 StyleLib, CDM 세트(`DDingUI_CDM`·`DDingUI_CDM_Option`·`DDingUI`·`DDingUI_Options` — CDM과 옵션은 항상 한 세트), Toolkit, RaidHelper, APL, FX만 버전 관리한다. Profile·UF·Branding은 디스크에만 두고 `.gitignore`에 있다. 일부 파일을 커밋하지 않은 것은 사용자의 의도이므로 임의로 `git add`하지 않는다.
- 모든 TOC의 `## Interface`는 `120000, 120001, 120005, 120007, 120100`으로 통일한다(UF 제외).
- 2026-08-26 대정리 때 격리한 파일: `C:\Users\D2JK\바탕화면\cd\DDingUI_cleanup_archive_20260826_5e1c3f31`

## DDingUI_RaidHelper 위치 및 설치 규칙
- 소스 폴더: `DDingUI_Super/DDingUI_RaidHelper/`
- `DDingUI_RaidHelper`는 `DDingUI` 폴더 하위 모듈이 아니라 Super 루트의 독립 애드온이다.
- Retail 설치 경로 `G:/wow2/World of Warcraft/_retail_/Interface/AddOns/DDingUI_RaidHelper`는 위 소스 폴더를 가리키는 디렉터리 심볼릭 링크로 유지한다. 정션은 권한 문제를 해결할 때만 임시 대안으로 사용하고, 가능해지면 심볼릭 링크로 교체한다. (2026-09-30 확인: 현재는 정션 상태)
- RaidHelper 파일은 소스 폴더에서만 수정하며 AddOns 경로에 별도 복사본을 만들지 않는다.
- 목적: 전투 중 이동하는 평균 공격대 피해 파형 위에 보스 기믹과 상위권 힐러 쿨기 시점을 함께 표시한다.
- 자동 선택: `ENCOUNTER_START`의 보스/난이도와 현재 플레이어 전문화를 조합해 맞는 데이터 팩을 수동 선택 없이 활성화한다.
- `ENCOUNTER_START`는 설치된 데이터 팩에 같은 보스 ID·난이도 모델이 있을 때만 엔진을 시작한다. 던전 보스와 데이터 없는 레이드 난이도에서는 빈 모델을 만들거나 타임라인·BigWigs 동기화를 시작하지 않는다.
- 데이터 갱신: 외부 갱신기가 Warcraft Logs 공개 API에서 보스·난이도별 스피드 상위 처치 10개와 7개 힐러 전문화별 HPS 상위 캐릭터 10명을 주기적으로 따로 집계한다.
- 집계 결과: 페이즈/기믹 정렬 후 0.5초별 평균 피해, 기믹 피해/피격 인원, 전문화별 쿨기 평균 시각/오차 범위/사용률, 평균 2차 스탯/아이템 레벨, 대표 특성 빌드/사용률을 Lua 데이터 팩으로 저장한다.
- WCL 데이터 팩에는 캐릭터 이름·서버·보고서 코드를 남기지 않는다. 특성 가져오기 문자열은 저장한 노드와 현재 게임 트리 해시로 런타임에 생성해 복사한다.
- 게임 안에서는 웹 요청을 하지 않으며, BigWigs 보스 바와 페이즈 신호로 현재 전투 타임라인을 재동기화한다.
- Midnight 12.0+에서는 `COMBAT_LOG_EVENT`와 `COMBAT_LOG_EVENT_UNFILTERED` 등록이 금지되므로 RaidHelper에서 절대 등록하거나 `CombatLogGetCurrentEventInfo()`를 사용하지 않는다. 실시간 정렬은 `ENCOUNTER_START`와 BigWigs 바/페이즈 메시지만 사용한다.
- BigWigs의 Encounter Timeline 메시지는 전투 중 `text`, `icon`, 남은 시간 등이 secret value일 수 있다. 반드시 `issecretvalue`로 거른 뒤 사용하고, secret 값을 `tostring`·비교·산술·테이블 키로 처리하거나 UI에 직접 전달하지 않는다. 바 추적과 중지·일시정지는 안전한 `eventID`/정적 key를 우선 사용한다.
- 전투창은 `Libs/DDingUI_StyleLib/`에 내장한 StyleLib의 색상·폰트·텍스처·디자인 토큰을 사용한다. 별도 `DDingUI_StyleLib` 애드온을 필수 의존성으로 두지 않는다.
- 전투창 모양(2026-10-10 사용자 선택, C안 릿지 바): 제목줄 없이 테두리 없는 바 하나(기본 70px) + 아래 힐러 쿨기 레일(28px). 바 양 끝은 너비의 12%씩 `Media/RaidHelper_FadeMask.tga` 마스크로 투명하게 페이드되고(`tools/build_fade_mask.py`로 생성, `UI/Timeline.lua`의 `FADE_SHARE`와 일치), 피해 파형은 바 바닥 능선, 기믹 아이콘은 바 위, 가장 가까운 기믹 1개만 상세 칩을 띄운다. 외곽선은 편집 중에만 악센트로 표시하며 견본 미리보기에서는 표시하지 않는다.
- 브랜딩은 `Branding/DDingUI_Symbol_Orange.png`의 알파와 형태를 유지해 RaidHelper 보라색(`#D65CFF`) 512×512 RGBA TGA로 변환한 `Media/RaidHelper_Icon.tga`를 사용한다. WoW 미니맵 스킨에서 원판으로 보이지 않도록 완전 투명 픽셀의 RGB도 0으로 만들고 TGA origin은 top-left로 저장한다.
- `tools/update_wcl.py`는 영웅·신화 전 보스를 난이도별 상위 공개 처치 로그 최대 10개로 자동 갱신한다.
- 신화 공개 처치가 없는 보스는 건너뛰며, 나중에 갱신기를 다시 실행하면 새로 공개된 보스를 자동 추가한다. WCL 시간당 한도는 초기화 시각까지 대기 후 자동 재개한다.
- WCL 자격 정보는 소스·데이터 팩에 저장하지 않고 Windows 사용자 환경 변수 `WCL_CLIENT_ID`, `WCL_CLIENT_SECRET`에서만 읽는다.
- 미니맵 버튼은 CDM·Toolkit과 같은 LibDataBroker/LibDBIcon 방식이다. 좌클릭으로 독립 설정 창을 열고 닫으며, 우클릭으로 전투 밖 타임라인 편집 모드를 시작/종료하고, 드래그 위치를 저장한다.
- 옵션은 블리자드 애드온 설정 카테고리에 등록하지 않는다. `UI/OptionsWindow.lua`가 내장 StyleLib만 사용해 Toolkit 수준의 `1차 카테고리 / 2차 페이지 목록 / 우측 상세` 3단 독립 GUI를 구성하며, 타임라인·미리보기/편집·쿨기 표시·힐러 프로필·데이터 팩 페이지를 제공한다.
- 독립 GUI의 1차 카테고리는 Toolkit과 동일한 배치로 RaidHelper 전용 제작 아이콘 `RaidTimeline.tga`, `HealerPlan.tga`, `LogData.tga`를 `Media/Navigation/`에 내장해 28px 단색 아이콘과 행 중앙의 한 줄 제목을 사용한다. 다른 DDingUI 애드온의 아이콘은 UI에서 사용하거나 런타임 참조하지 않는다. 숫자 인덱스·2줄 설명형 메뉴는 사용하지 않으며, 2차 페이지 제목/설명은 상태점이 아닌 행의 정수 좌표에 직접 고정해 반 픽셀 글자 흐림을 피한다.
- 독립 설정 창은 설치된 영웅·신화 모델 수와 최근 생성 시각을 표시하고, 전투 밖에서만 UI 리로드로 데이터 팩을 다시 읽는다.
- 게임 실행 중 새 애드온 링크를 만든 첫 설치에서는 `/reload`만으로 폴더가 검색되지 않을 수 있으므로 WoW를 완전히 재시작하고 애드온 목록에서 RaidHelper 활성화를 확인한다. StyleLib는 내장되어 있어 별도 활성화가 필요 없다.
- 마커 툴팁은 승인된 SavedVariables 키 `showTooltips`로 저장하며 기본값은 `false`다. 전투 중 변경은 즉시 반영하지 않고 `PLAYER_REGEN_ENABLED`에서 적용한다.
- "리마인더"(옛 이름 "곧 사용 알림", 2026-10-10 사용자 요청으로 화면 이름만 변경·저장 키는 그대로) 예정 쿨기 알림: NSRT 메모처럼 아이콘·스킬 이름·남은 초로 표시하고, 가장 가까운 쿨기 하나만 3초 전부터 일본어 "さん·に·いち"(VOICEVOX:猫使ビィ 기본 음색) 음성(`Media/Sounds/Countdown_{1,2,3}.ogg`, `tools/build_countdown_voice.py`, Master 채널)으로 센다. 켜고 끄기는 승인된 SavedVariables 키 `countdownVoice`(기본 `true`)이며 소리만 바꾸므로 전투 중에도 즉시 적용한다. 미리보기/편집 중에는 소리를 내지 않는다. 알림 세부 모양(2026-10-10 사용자 요청)은 승인된 키 `alertStyle = {iconSize, nameSize, countSize, spacing, maxRows, width, window, align, grow, showIcon, showName, pop}` 하나에 저장하고, 기본값·범위는 `UI/Timeline.lua`의 `ALERT_STYLE_SPEC`이 단일 출처다(빈 표 = 기본값, 잘못된 값은 범위 안으로 보정). 설정창 "화면 → 곧 사용 알림" 페이지가 알림 켜기·음성 카운트·견본·크기·배치·요소를 모두 맡고, 알림은 애드온 자체의 보호되지 않은 프레임이라 모양 변경은 전투 중에도 즉시 적용한다.
- 타임라인 전체 크기·너비·높이·배경 불투명도는 승인된 SavedVariables 키 `timelineScale`(기본 1.0, 0.6~1.6), `timelineWidth`(기본 680, 200~1200), `timelineHeight`(바+레일 전체, 기본 98, 80~160 — 이전 4단 창 값 170 이상은 98로 되돌림), `backgroundAlpha`(기본 1.0, 0~1)로 저장한다. 배경 값은 글자·아이콘·파형이 아닌 바 배경과 지난 구간 음영에만 곱하며(0%면 파형·아이콘만 뜸), 전투 중 변경은 `PLAYER_REGEN_ENABLED`에서 적용한다.
- 미리보기·편집 분리(2026-10-10): 페이지 미리보기와 `/drh preview|demo|test`는 설정 창을 유지한 채 기존 Demo를 실제 타임라인·리마인더로 반복 재생하는 읽기 전용 견본이다. 마우스 드래그·격자·HUD·리모컨을 끄고 설정 창 위에 표시하며, 저장 위치와 `alertPosition` 연결 상태를 바꾸지 않는다. 설정 창 닫기·전투 진입·미리보기 종료로 멈춘다. 제목줄 편집 버튼·미니맵 우클릭·`/drh edit|move|unlock`은 위치 편집 전용이다. `IsPreviewMode()`는 두 견본 실행을 모두 포함해 전투 종료 처리와 무음 정책을 유지하며, `IsEditSessionActive()`만 편집 표시·드래그·제목줄 상태를 제어한다. 새 저장 키와 견본 데이터 변경은 없다.
- 위치 편집 모드(2026-10-03, 시리즈 C12): StyleLib 1.4 공용 리모컨·HUD·격자·스냅을 쓴다. 리모컨 위치는 승인된 SavedVariables 키 `editRemotePos = {point, x, y}`에만 저장하며 격자·스냅 상태는 저장하지 않는다. 편집 모듈은 둘이다(2026-10-10 사용자 요청): "공격대 타임라인"(`position`)과 "곧 사용 알림"(승인된 키 `alertPosition = {point, relativePoint, x, y}`, 없으면 타임라인 아래 6px에 붙은 옛 배치). 첫 편집 진입 때 알림을 제자리에서 분리해 저장하고, 리모컨 프레임 선택·클릭으로 고른 모듈만 넛지·X/Y·초기화·실행 취소한다. 알림은 타임라인 프레임의 자식이라 페이드·전체 크기는 함께 따르며, 편집 중에만 마우스를 받는다. "프레임" 스냅은 다른 모듈 가장자리와 화면 가장자리에 맞춘다. `PLAYER_REGEN_DISABLED`와 `ENCOUNTER_START`에서 견본 실행을 종료한다. 편집 모드만 진입 시 설정창을 닫고 종료 시 다시 연다.
- 독립 설정창 크기는 승인된 SavedVariables 키 `optionsScale`(기본 1.0, 0.5~1.5)로 저장한다. 제목줄 닫기 버튼 왼쪽의 StyleLib 공통 "GUI 크기" 컨트롤이 바꾸며, 창의 열기/닫기 모션 기준 배율(`SetBaseScale`)로 적용한다. 전투 타임라인 크기(`timelineScale`)와는 별개다.
- 힐러 쿨기 표시는 `cooldownVisibility[specID][spellID]`에 저장한다. 주요 힐업·세미 쿨기·외생기·개인/유틸 그룹과 전문화별 체크박스를 제공하며, 신성 사제 후광(120517)을 포함한 세미 쿨기도 수집한다. 전투 중 변경은 즉시 반영하지 않는다.
- 사용자 요청(2026-08~09): 쿨기 시점은 여러 로그의 중앙값이 아니라 가장 많이 쓴 구간을 기준으로 잡는다. 현재 `tools/wcl_pipeline.py`는 시간 군집을 만든 뒤 사용률 하한을 넘는 군집 안에서 중앙값을 쓴다. 이 요청이 완전히 반영됐는지는 확인되지 않았으므로, 쿨기 정렬을 수정할 때 사용자에게 기준을 확인한다.
- 로그 타이밍은 사용 순번 평균이 아니라 페이즈 안 시간 군집 기준으로 정렬하고, 공통 광역 기믹으로 피해 파형을 보정한다. 전문화별 상위 HPS 로그의 쿨기는 해당 로그의 적대 시전 앵커를 기준 모델의 기믹 축에 구간 보간해 `phase-mechanic-warped` 시각으로 저장한다.
- WCL `hostilityType: Enemies` 시전 중 `sourceID <= 0`인 Environment 합성 이벤트와 Player/Pet 시전은 보스 앵커로 절대 사용하지 않는다. 화면 기믹 선정에서 빠지는 저피해/단일 대상 기술도 `syncAnchors`에 유지해 BigWigs 실제 남은 시간, 일시정지·재개 신호가 피해·기믹·힐러 쿨기 전체 축을 함께 재동기화하게 한다.

## 핵심 규칙
- 리마인더 모션(2026-10-10): 최종 승인 목업대로 0.25초 등장(왼쪽 10px), 3초 틴트·시간 선·아이콘 숨빛·숫자 팝, 0.4초 ‘지금’ 반짝임, -0.45~-0.75초 퇴장(위 6px), 0.2초 줄 이동을 `UI/Timeline.lua`에 적용했다. 기존 `alertStyle.pop`의 값과 기본값을 유지해 ‘모션’ 스위치로 전체 효과를 제어하며 새 저장 키는 없다. 스킬 데이터별로 줄 프레임을 유지하고 전투 시작·미리보기 반복·종료 때 모션 상태를 정리한다. 설정 견본은 정적이고 미리보기의 음성 무음 동작은 유지한다.
- 변경 작업은 관련 검증을 마친 뒤 반드시 커밋까지 완료한다. 기존 미커밋 변경과 이번 작업은 구분해 커밋하며, 버전 관리 제외 파일은 추가하지 않는다.
- 코드 치기 전에 생각하기
- 건드리는 건 최소한으로
- 목표를 명확히 하라
- 단순하게 가라
- DB 구조 변경 금지
- 모든 UI 색상은 StyleLib.Colors 참조
- 변경 주석: -- [REFACTOR], -- [STYLE], -- [12.0.1]
- 저장소 안에 `_backup/` 복사본을 만들지 않으며, 추적 파일은 Git 이력·태그로 복구하고 미추적 파일은 필요 시 저장소 밖에 임시 격리

## 애드온별 악센트
- StyleLib 참고

## 공통 의존성
- StyleLib는 각 애드온의 Libs/DDingUI_StyleLib/에 임베드
- 원본은 `DDingUI_StyleLib/`(Lua 19파일 + `Media/`)다. 공유 이름(`DDingUI-StyleLib-1.0`, MINOR 7)을 쓰는 CDM·Toolkit·Profile·APL 사본은 원본과 바이트 단위로 같고, RaidHelper·FX 사본은 비공개 이름(`DDingUI-RaidHelper-StyleLib-1.0`/`DDingUI-FX-StyleLib-1.0`)과 전역 이름 줄만 다르다(FX는 TOC가 읽는 7파일만). UF 사본은 개발 중지라 옛 버전 그대로 두며 동기화에서 제외한다.
- **StyleLib를 고치면 반드시 동기화한다:** `python DDingUI_StyleLib/tools/sync_stylelib.py`. 원본 또는 아무 사본이나 고쳐도 된다 — 사본을 고쳤으면 `--from <고친 파일>`로 원본에 되돌려 넣은 뒤 전 사본에 퍼뜨린다(비공개 이름은 자동 변환). Claude Code는 `.claude/settings.json`의 PostToolUse 훅(`DDingUI_StyleLib/tools/stylelib_hook.py`)이 편집 직후 자동 실행하고, Codex 등 다른 도구는 직접 실행한다. 검사: `--check`(차이 있으면 종료 코드 1), 루트 `test_stylelib_sync.py`. 원본에 없는 파일이 사본에 있으면 삭제하지 않고 보고만 한다.
- `Media/` 텍스처(둥근 9분할 마스크 `ddsl_round{2,3,4,6,8,10,14}[_border]`, 로고 고리 `ddsl_rings`/`ddsl_ring_left`/`ddsl_ring_right`, 슬라이더 손잡이 `ddsl_thumb_rings`)는 `DDingUI_StyleLib/tools/build_media.py`로 만든다(원본 `Branding/DDingUI_Symbol_Orange.png`). 손으로 고치지 말고 스크립트를 고쳐 다시 만든 뒤 모든 사본의 `Media/`에 복사한다.
- 설정창 디자인 기준은 시안 7(2026-09-30 확정): 창 반경 14 + 안쪽 8px 둥근 카드(10), 알약 선택 표시(8), 컨트롤 6·체크 4·트랙 2, 로고 고리 모티브(제목줄 로고 연결 애니메이션·섹션 고리 표시·고리 캡슐 손잡이·상태 고리·워터마크). 전투 HUD는 대상이 아니다.
- 미니맵 버튼은 StyleLib `CreateMinimapButton(opts)`/`AddMinimapTooltip`으로 만든다(LibDataBroker-1.1·LibDBIcon-1.0 내장 필요).

<!-- code-review-graph MCP tools -->
## MCP Tools: code-review-graph

**This project has a knowledge graph. Start with the code-review-graph
MCP tools to narrow scope, then read the source.** The graph is cheaper than scanning files and
gives you structural context (callers, dependents, test coverage) that file search cannot.

### When to use graph tools FIRST

- **Exploring code**: `semantic_search_nodes_tool` or `query_graph_tool` instead of Grep
- **Understanding impact**: `get_impact_radius_tool` instead of manually tracing imports
- **Code review**: `detect_changes_tool` + `get_review_context_tool` instead of reading entire files
- **Finding relationships**: `query_graph_tool` with callers_of/callees_of/imports_of/tests_for
- **Architecture questions**: `get_architecture_overview_tool` + `list_communities_tool`

### Verify in the source

- Narrow scope with the graph, then read the source. Do not change code from graph output alone.
- For any non-trivial change, read the implementation and the relevant tests before concluding.
- Verify the exact source when touching behavior, database logic, migrations, retries, fallbacks,
  recovery, or compatibility code.
- When the graph and the source disagree, the source wins. The graph may be stale or may not
  model that relationship.
- An empty graph result can mean "not indexed" or "not statically visible", not "does not exist".

### Key Tools

| Tool | Use when |
| ------ | ---------- |
| `detect_changes_tool` | Reviewing code changes — gives risk-scored analysis |
| `get_review_context_tool` | Need source snippets for review — token-efficient |
| `get_impact_radius_tool` | Understanding blast radius of a change |
| `get_affected_flows_tool` | Finding which execution paths are impacted |
| `query_graph_tool` | Tracing callers, callees, imports, tests, dependencies |
| `semantic_search_nodes_tool` | Finding functions/classes by name or keyword |
| `get_architecture_overview_tool` | Understanding high-level codebase structure |
| `refactor_tool` | Planning renames, finding dead code |

### Workflow

1. The graph auto-updates on file changes (via hooks).
2. Use `detect_changes_tool` for code review.
3. Use `get_affected_flows_tool` to understand impact.
4. Use `query_graph_tool` pattern="tests_for" to check coverage.
<!-- /code-review-graph MCP tools -->
