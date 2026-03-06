# DDingUI UnitFrames

**Minimal, but never lacking.**
**미니멀하지만, 부족한 건 없습니다.**

A complete unit frame replacement for World of Warcraft, rebuilt from scratch. Every unnecessary decoration has been stripped away — only the information that matters in combat remains. Beneath the clean exterior lies an extensive option system where nearly every element can be fine-tuned down to the pixel.

WoW의 유닛 프레임을 처음부터 다시 설계했습니다. 불필요한 장식은 걷어내고, 전투에서 진짜 필요한 정보만 남겼습니다. 깔끔한 외형 아래에는 거의 모든 요소를 픽셀 단위로 조절할 수 있는 방대한 옵션이 숨어 있습니다.

---

## HoT Tracker — Your Heals at a Glance | HoT 트래커 — 내 치유를 한눈에

For healers, the most critical question is always: **"Who has what on them right now?"**

힐러에게 가장 중요한 건 **"지금 누구에게 뭐가 걸려 있는가"** 입니다.

DDingUI UF's HoT Tracker displays your active heal-over-time effects directly on raid frames with instant visual feedback. From a Restoration Druid's Rejuvenation and Wild Growth to a Holy Priest's Renew and Atonement — choose which buffs to track per specialization, and configure each buff's display individually.

DDingUI UF의 HoT 트래커는 내가 시전한 지속 치유를 레이드 프레임 위에 직관적으로 표시합니다. 회복 드루이드의 회생, 야생 성장부터 신성 사제의 갱신, 속죄까지 — 직업/전문화별로 추적할 버프를 자유롭게 선택하고, 각 버프마다 표시 방식을 개별 설정할 수 있습니다.

### 4 Visualization Modes per Buff | 버프별 4가지 시각화 방식

Mix and match to build your own visual language:

4가지를 조합해서 나만의 시각 체계를 만들 수 있습니다:

| Mode | Description | 설명 |
|------|-------------|------|
| **Color Bar** | Thin colored bar on top/bottom of the frame. Adjustable thickness & color. | 프레임 상단/하단에 얇은 색상 막대 표시. 두께·색상 자유 조절 |
| **Gradient Overlay** | Subtle color wash across the entire frame for instant identification. | 프레임 전체에 은은한 색상을 깔아 한눈에 식별 |
| **Health Bar Tint** | Changes the health bar color itself when a HoT is active. | HoT가 걸린 대상의 체력바 색 자체를 변경해 즉각 인지 |
| **Outline Glow** | Colored border around the frame for maximum visibility. | 프레임 테두리를 색상으로 감싸 시인성 극대화 |

All four can be enabled simultaneously or individually. Assign Rejuvenation a green bar, Lifebloom a pink overlay — give each buff its own visual identity, and HoT coverage across a 20-player mythic raid becomes readable at a glance.

4가지를 동시에 켤 수도, 하나만 쓸 수도 있습니다. 회생은 초록 바, 생명의 꽃은 분홍 오버레이 — 버프마다 다른 시각 언어를 부여하면, 20인 신화 레이드에서도 HoT 현황이 한 번에 들어옵니다.

---

## Clean Composition — A UI That Stays Out of Your Way | 깔끔한 구성 — 전투에 집중하는 UI

Inspired by Cell's grid-based approach, frames align naturally from party to mythic raid.

Cell에서 영감을 받은 격자 기반 레이아웃으로, 파티부터 신화 레이드까지 인원수에 맞게 자연스럽게 정렬됩니다.

### Key Design Features | 핵심 디자인

- **3-Tier Frame Separation** — Party (5) / Normal·Heroic Raid (10–30) / Mythic Raid (20) each have independent settings. Automatically switches when entering a mythic raid instance.

  **3단계 프레임 분리** — 파티(5인) / 일반·영웅 공격대(10~30인) / 신화 공격대(20인)를 각각 독립된 설정으로 관리. 신화 레이드 입장 시 자동으로 전환됩니다.

- **Pixel-Perfect Rendering** — A 1-pixel border is exactly 1 pixel regardless of resolution. No blurry or smeared edges.

  **픽셀 퍼펙트 렌더링** — 해상도에 관계없이 테두리 1픽셀이 정확히 1픽셀. 번지거나 흐릿한 선이 없습니다.

- **Heal Prediction Bar** — Incoming heals shown as a translucent overlay on the health bar, helping you avoid overhealing.

  **치유 예측 바** — 들어올 치유량을 체력바 위에 반투명하게 표시해, 과힐 없이 효율적인 치유 판단을 돕습니다.

- **Debuff Highlight** — When a dispellable debuff is detected, the entire frame glows in the debuff type's color.

  **디버프 하이라이트** — 해제 가능한 디버프 감지 시 프레임 전체를 디버프 유형 색상으로 강조합니다.

- **Range Fade** — Targets out of healing range automatically dim, naturally guiding your visual priority.

  **사거리 페이드** — 치유 사거리 밖의 대상은 자동으로 어두워져, 시선 우선순위가 자연스럽게 정리됩니다.

Every unit frame — player, target, target-of-target, focus, boss, arena — shares one consistent design language.

플레이어·대상·대상의 대상·주시 대상·보스·투기장 프레임까지, 모든 유닛 프레임이 하나의 일관된 디자인 언어로 통일되어 있습니다.

---

## Every Detail, Your Way | 세세한 옵션 — 모든 것을 당신 손으로

Type `/duf` to open the settings panel. Nearly every visual element is adjustable.

`/duf` 한 줄이면 열리는 설정 패널에서, 프레임의 거의 모든 요소를 조절할 수 있습니다.

### Independent Settings per Frame | 프레임별 독립 설정

Player · Target · Focus · Party · Raid · Mythic Raid · Boss · Arena — **each unit frame has its own complete set of options**. The same health bar can be large on your player frame and compact on the raid grid.

플레이어·대상·주시 대상·파티·레이드·신화 레이드·보스·투기장 — **각 유닛 프레임이 완전히 독립된 설정**을 가집니다. 같은 체력바라도 플레이어 프레임에선 크게, 레이드에선 작게 — 용도에 맞게 따로 조절합니다.

### What You Can Customize | 조절 가능한 항목

| Category | Options | 설명 |
|----------|---------|------|
| **Size & Position** | Width, height, drag placement, grid snap, anchor point | 너비, 높이, 드래그 이동, 격자 스냅, 앵커 포인트 |
| **Health Bar** | Color type (class/reaction/custom), background, health loss color, fill direction | 색상 타입(직업색/반응색/고정색), 배경색, 손실 체력 색상, 채움 방향 |
| **Power Bar** | Height, fill direction, detached/integrated display | 높이, 채움 방향, 분리/통합 표시 |
| **Cast Bar** | Position, size, timer offset, uninterruptible color | 위치, 크기, 타이머 오프셋, 인터럽트 불가 색상 |
| **Text** | Name · Health · Power · Level — font, size, position, format (%, current, current/max, etc.) | 이름·체력·자원·레벨 — 폰트, 크기, 위치, 포맷(%, 현재값, 현재/최대 등) |
| **Buffs / Debuffs** | Icon size, max count, duration display, sort direction, filtering | 아이콘 크기, 최대 개수, 지속시간 표시, 정렬 방향, 필터링 |
| **Layout** | Growth direction, group spacing, unit spacing, max groups, role/group sorting | 성장 방향, 그룹 간격, 유닛 간격, 최대 그룹 수, 역할별/그룹별 정렬 |
| **Border** | Thickness, color | 두께, 색상 |
| **Background** | Color, opacity | 색상, 투명도 |

### Number Format | 숫자 표시 형식

Display health values in **Eastern format (1.2만, 3.4억)** or **Western format (12.3K, 1.5M)**, with adjustable decimal places (0–3). Changes apply instantly to all frames.

체력 수치를 **동양식(1.2만, 3.4억)** 또는 **서양식(12.3K, 1.5M)**으로 표시할 수 있으며, 소수점 자릿수(0~3)도 자유롭게 조절됩니다. 설정 변경 즉시 모든 프레임에 반영됩니다.

### Media | 미디어 커스터마이징

- **Textures** — Hundreds of status bar textures via LibSharedMedia
- **Fonts** — Use any font installed on your system

- **텍스처** — LibSharedMedia를 통해 수백 종의 상태바 텍스처 지원
- **폰트** — 시스템에 설치된 모든 폰트 사용 가능

### Profiles | 프로필 시스템

Save your settings as profiles and share them across characters. Export a profile as a string and import it on another character — easy sharing.

설정을 프로필로 저장하고, 캐릭터 간에 공유할 수 있습니다. 문자열로 내보내기/가져오기하여 다른 캐릭터에서도 동일한 설정을 사용할 수 있습니다.

### Edit Mode | 편집 모드

Enter edit mode with `/duf edit` to drag-and-drop all frames with grid snapping. Use the nudge panel for precise anchor and offset adjustments. Preview raid/mythic layouts before entering an instance.

`/duf edit`로 편집 모드에 진입하면, 모든 프레임을 드래그로 배치하고 격자에 스냅할 수 있습니다. 넛지 패널에서 앵커·오프셋을 수치로 미세 조정하는 것도 가능합니다. 레이드/신화 전환 프리뷰로 실제 배치를 미리 확인할 수 있습니다.

---

## At a Glance | 한눈에 보기

| | EN | KR |
|---|---|---|
| **Style** | Minimal + Pixel Perfect | 미니멀 + 픽셀 퍼펙트 |
| **HoT Tracker** | 4 visualizations × individual colors per buff | 버프별 4가지 시각화 × 개별 색상 |
| **Group Frames** | Party / Raid / Mythic Raid — 3-tier split | 파티 / 레이드 / 신화 레이드 3단 분리 |
| **Options** | Every unit × every element independently | 모든 유닛 × 모든 요소 독립 설정 |
| **Compatibility** | WoW 12.0.1+ (The War Within) | WoW 12.0.1+ (내부 전쟁) |
| **Profiles** | Export / Import via string | 문자열 내보내기 / 가져오기 |

---

## Slash Commands | 슬래시 명령어

| Command | Description | 설명 |
|---------|-------------|------|
| `/duf` | Open settings panel | 설정 패널 열기 |
| `/duf edit` | Toggle edit mode | 편집 모드 전환 |
| `/duf test` | Toggle test mode (dummy frames) | 테스트 모드 전환 (더미 프레임) |
| `/duf reset` | Reset frame positions | 프레임 위치 초기화 |

---

*Clean by default. Detailed by choice. Design your UI, your way.*

*깔끔함은 기본, 디테일은 선택. 당신의 UI를 당신이 설계하세요.*
