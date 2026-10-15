# DDingUI RaidHelper Changelog

## 2.1.3

2026-10-15

### 한국어

- WoW 12.1.5 인터페이스를 지원합니다.
- 2.1.2의 한국어·영어·경보 카운트와 기존 일본어를 포함한 4종 선택, 타임라인 표시 요소·아이콘 크기·시간 범위 설정을 포함합니다.
- 연속 피해의 반복 틱을 한 기믹 아이콘으로 묶어 타임라인이 같은 아이콘으로 가득 차지 않도록 했습니다. 피해 파형과 BigWigs 동기화 정보는 유지합니다.
- 리마인더 위치를 처음 표시할 때부터 화면 경계 안에 맞춰, 편집 모드 사용 전후 위치가 달라지는 문제를 수정했습니다.

### English

- Added WoW 12.1.5 interface support.
- Includes the four countdown choices (Korean, English, alarm and the existing Japanese) and timeline visibility, icon-size and time-range settings introduced in 2.1.2.
- Collapsed repeated ticks of continuous damage into one mechanic icon while retaining the damage wave and BigWigs synchronization data.
- Applied screen bounds to reminders from their first appearance, so entering edit mode no longer changes their positioning rules.

## 2.1.2

2026-10-11

### 한국어

- 리마인더에 한국어·영어·경보 카운트를 내장하고 기존 일본어와 함께 4종을 선택하도록 추가했습니다. 기존 일본어와 카운트 켜기/끄기 설정은 유지되며 전투 중 선택과 미리 듣기에 바로 적용됩니다.
- 타임라인 세부 설정을 추가했습니다. 기믹 아이콘 크기(16~40)·쿨기 아이콘 크기(12~32), 지난 시간(2~30초)·앞으로 표시할 시간(10~90초), 지난 아이콘 불투명도(0%면 숨김)를 조절하고, 기믹 아이콘·쿨기 아이콘·기믹 남은 초·기믹 상세·쿨기 이름·쿨기 오차 범위·가까운 기믹 강조·피해 파형·페이즈 표시·시간 눈금·전투 시간을 하나씩 켜고 끌 수 있습니다. 기본값은 지금 모양 그대로이며 “기본값으로”로 되돌립니다. 쿨기 아이콘을 꺼도 리마인더는 계속 알려 줍니다.
- 전투 중 바꾼 타임라인 설정은 전투 종료 후 적용됩니다. 작은 타임라인에서 남은 초와 상세 설명이 쿨기 레일로 넘치는 문제를 수정했습니다.
- 선정된 보스 주요 기믹만 표시하도록 수정했습니다. 동기화용 BigWigs 바 추적은 유지합니다.
- 주술사 세 전문화의 승천 새 아이콘이 타임라인과 리마인더에 표시되도록 수정했습니다.

### English

- Bundled Korean, English and alarm countdowns alongside the existing Japanese pack. Reminder settings now offer four choices, applied immediately to live counts and sound previews while preserving existing Japanese and on/off settings.
- Added timeline detail settings: mechanic icon size (16–40), cooldown icon size (12–32), past (2–30 s) and upcoming (10–90 s) time range, and past-icon opacity (0% hides them), plus individual switches for mechanic icons, cooldown icons, mechanic countdowns, mechanic details, cooldown names, cooldown timing bands, the nearest-mechanic highlight, the damage ridge, phase markers, time ticks and the fight timer. Defaults keep the current look and a reset button restores them. Reminders keep working when cooldown icons are hidden.
- Timeline settings changed during combat apply after combat ends. Fixed countdowns and detail labels overflowing into the cooldown rail on short timelines.
- Fixed the display to show only selected major boss mechanics while retaining BigWigs bar tracking for synchronization.
- Fixed the updated Ascendance icons for all three shaman specializations on the timeline and reminders.

## 2.1.1

2026-10-10

### 한국어

- 애드온과 설정창 버전 표기를 2.1.1로 맞췄습니다.
- 일본어 “さん·に·いち” 카운트 음성(VOICEVOX:猫使ビィ)과 출처 표기를 애드온에 내장했습니다.
- 데이터 갱신용 BAT 파일과 설정창의 관련 실행 안내를 제거했습니다. Python 외부 데이터 갱신기는 유지합니다.
- "곧 사용 알림"의 이름을 "리마인더"로 바꿨습니다(편집 모듈·설정 페이지·안내 문구). 저장 데이터는 그대로입니다.
- 리마인더에 등장·퇴장·줄 이동, 3초 강조와 시간 선, 숫자 팝, ‘지금’ 반짝임을 적용했습니다. 기존 ‘3초 강조 효과’ 설정을 ‘모션’으로 바꿔 전체 효과를 제어하며 저장값은 유지합니다.
- 미리보기와 위치 편집을 분리했습니다. 미리보기는 설정 창을 유지하며 실제 전투 UI로 견본을 반복 재생하고, 리모컨·격자·이동 표시와 위치 저장은 편집 모드에서만 사용합니다.

### English

- Updated the addon and settings-window version labels to 2.1.1.
- Bundled the Japanese three-two-one voice countdown (VOICEVOX:猫使ビィ) and its attribution with the addon.
- Removed the data-update BAT file and related execution instructions from settings. The external Python data updater remains available.
- Renamed the "upcoming cooldown alert" to "Reminder" in the edit module, settings page and messages. Saved data is unchanged.
- Added reminder entrance, exit and row transitions, a three-second highlight and time line, number pops and a flash at the scheduled time. The existing highlight toggle now controls all motion and retains its saved value.
- Separated the demo preview from position editing. Preview keeps settings open and loops the actual combat UI; the remote, grid, position overlays and position saving are limited to edit mode.

## 2.1.0

2026-10-10

### 한국어

- 애드온과 설정창 버전 표기를 2.1.0으로 맞췄습니다. 기존 기능과 데이터는 유지합니다.
- 양 끝이 부드럽게 사라지는 테두리 없는 타임라인에 피해 파형·보스 기믹·쿨기 레일을 표시합니다.
- 곧 사용할 쿨기를 아이콘·스킬 이름·남은 초로 보여 주고, 가장 가까운 하나를 일본어 “さん·に·いち” 음성으로 알립니다(VOICEVOX:猫使ビィ).
- 데이터 갱신용 BAT 파일과 설정창의 BAT 파일명·외부 수집 실행 안내를 제거했습니다.
- 타임라인과 곧 사용 알림을 각각 옮기고, 알림의 크기·정렬·성장 방향·글자와 표시 요소를 설정할 수 있습니다.
- 피해 파형과 BigWigs 재동기화의 시간 보정, 설정 페이지 스크롤과 알림 견본의 잘림을 수정했습니다.

### English

- Set the addon and settings-window version labels to 2.1.0, retaining existing features and data.
- A borderless timeline with fading edges shows damage waves, boss mechanics and a cooldown rail.
- Upcoming cooldowns show an icon, spell name and seconds remaining, with a Japanese three-two-one voice countdown for the nearest one (VOICEVOX:猫使ビィ).
- Removed the data-update BAT file. Settings no longer show its filename or instructions for external data collection.
- Move the timeline and upcoming alerts separately, and adjust alert size, alignment, growth direction, text and visible elements.
- Fixed timing corrections for damage waves and BigWigs resynchronization, settings-page scrolling and clipped alert previews.
