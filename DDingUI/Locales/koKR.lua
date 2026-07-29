--[[
    DDingUI Localization - Korean (koKR)
    한국어 번역
--]]

local L = LibStub("AceLocale-3.0"):NewLocale("DDingUI", "koKR")

if not L then return end

L["Add Trinket Buff"] = "강화효과 추가"
L["Remove Trinket Buff"] = "강화효과 제거"

-- ============================================================
-- GENERAL
-- ============================================================
L["DDingUI"] = "띵UI"
L["Left-click to open configuration"] = "좌클릭: 설정 열기"
L["Right-click to open configuration"] = "우클릭: 설정 열기"
L["Right-click to toggle move mode"] = "우클릭: 이동모드 전환"

-- ============================================================
-- CONFIG - GENERAL OPTIONS
-- ============================================================
L["Disabled"] = "비활성화됨"
L["Settings"] = "설정"
L["Options"] = "옵션"

-- ============================================================
-- CONFIG - RESOURCE BARS
-- ============================================================
L["Track a specific buff's stacks and display as a resource bar. Useful for tracking buffs like Fury Warrior's Whirlwind."] = "특정 버프의 중첩을 추적하여 자원 바로 표시합니다. 분노 전사의 소용돌이 같은 버프 추적에 유용합니다."
L["The spell ID of the buff to track. Example: 85739 for Whirlwind (Fury Warrior)"] = "추적할 버프의 주문 ID. 예: 85739 (분노 전사의 소용돌이)"
L["Maximum number of stacks for the buff"] = "버프의 최대 중첩 횟수"
L["Hide When Zero Stacks"] = "중첩 0일 때 숨기기"
L["Hide When Zero"] = "0일 때 숨기기"
L["Hide charge/stack text when count is 0"] = "사용횟수/중첩이 0일 때 텍스트 숨기기"
L["Hide the bar when the buff has no stacks"] = "버프 중첩이 없을 때 바 숨기기"
L["Show Stack Count"] = "중첩 횟수 표시"
L["Display current stack count as text"] = "현재 중첩 횟수를 텍스트로 표시"
L["Color of the buff tracker bar"] = "커스텀 오라 바 색상"
L["Track a specific buff's stacks and display as a resource bar. Example: Fury Warrior's Whirlwind buff (Spell ID: 85739)."] = "특정 버프의 중첩을 추적하여 자원 바로 표시합니다. 예: 분노 전사의 소용돌이 버프 (주문 ID: 85739)."
L["Background color for the bar"] = "바의 배경 색상"
-- 수동 추적 모드 (IWT 방식)
L["Choose how to track the buff. 'Buff API' uses Blizzard's aura system. 'Manual (Spell Cast)' tracks spell casts like ImprovedWhirlwindTracker - more reliable for some buffs during combat."] = "버프 추적 방식을 선택합니다. '버프 API'는 블리자드의 오라 시스템을 사용합니다. '수동 (주문 시전)'은 ImprovedWhirlwindTracker처럼 주문 시전을 추적합니다 - 전투 중 일부 버프에 더 신뢰성이 높습니다."
L["Buff API (Default)"] = "버프 API (기본)"
L["Manual (Spell Cast)"] = "수동 (주문 시전)"
L["Manual mode tracks spell casts instead of buff state. Configure generator spells (gain max stacks) and spender spells (consume 1 stack). Example for Fury Warrior Whirlwind: Generators=190411,6343,435222 Spenders=23881,85288,280735"] = "수동 모드는 버프 상태 대신 주문 시전을 추적합니다. 생성기 주문(최대 중첩 획득)과 소모기 주문(1중첩 소모)을 설정하세요. 분노 전사 소용돌이 예시: 생성기=190411,6343,435222 소모기=23881,85288,280735"
L["Generator Spell IDs"] = "생성기 주문 ID"
L["Comma-separated spell IDs that grant max stacks. Example: 190411,6343,435222 for Whirlwind, Thunder Clap, Thunder Blast"] = "최대 중첩을 부여하는 주문 ID (쉼표로 구분). 예: 190411,6343,435222 (소용돌이, 천둥벼락, 천둥 질풍)"
L["Spender Spell IDs"] = "소모기 주문 ID"
L["Comma-separated spell IDs that consume 1 stack. Example: 23881,85288,280735 for Bloodthirst, Raging Blow, Execute"] = "1중첩을 소모하는 주문 ID (쉼표로 구분). 예: 23881,85288,280735 (피의 갈증, 광기의 일격, 처형)"
L["Stack Duration"] = "중첩 지속시간"
L["How long stacks last before expiring (seconds)"] = "중첩이 만료되기 전까지 지속되는 시간 (초)"
L["How long stacks last before expiring (seconds). Set to 0 for unlimited duration."] = "중첩이 만료되기 전까지 지속되는 시간 (초). 0으로 설정하면 무제한 지속됩니다."
L["Reset On Combat End"] = "전투 종료 시 초기화"
L["Reset stacks to zero when leaving combat"] = "전투를 벗어나면 중첩을 0으로 초기화"
L["Presets"] = "프리셋"
L["Fury Warrior - Whirlwind"] = "분노 전사 - 소용돌이"
L["Auto-fill settings for tracking Fury Warrior's Whirlwind buff stacks"] = "분노 전사의 소용돌이 버프 중첩 추적 설정을 자동으로 채웁니다"
L["Fury Warrior Whirlwind preset applied!"] = "분노 전사 소용돌이 프리셋이 적용되었습니다!"
L["Havoc DH - Momentum"] = "파멸 악사 - 갈무리한 기운"
L["Auto-fill settings for tracking Havoc Demon Hunter's Momentum buff duration"] = "파멸 악마사냥꾼의 갈무리한 기운 버프 지속시간 추적 설정을 자동으로 채웁니다"
L["Havoc DH Momentum preset applied!"] = "파멸 악사 갈무리한 기운 프리셋이 적용되었습니다!"
L["BM Hunter - Frenzy"] = "야수 사냥꾼 - 광기"
L["Auto-fill settings for tracking Beast Mastery Hunter's Frenzy buff stacks"] = "야수 사냥꾼의 광기 버프 중첩 추적 설정을 자동으로 채웁니다"
L["BM Hunter Frenzy preset applied!"] = "야수 사냥꾼 광기 프리셋이 적용되었습니다!"
L["Display Mode"] = "표시 모드"
L["Choose what the bar displays: stack count or remaining duration"] = "바에 표시할 내용 선택: 중첩 횟수 또는 남은 지속시간"
L["Generator Behavior"] = "생성기 동작"
L["How generator spells affect stacks: 'Set Max' instantly fills to max stacks (like Whirlwind), 'Add One' adds 1 stack per cast (like Frenzy)"] = "생성기 주문이 중첩에 미치는 영향: '최대 설정'은 최대 중첩으로 즉시 채움 (소용돌이), '1중첩 추가'는 시전당 1중첩 추가 (광란)"
L["Set Max Stacks"] = "최대 중첩 설정"
L["Add One Stack"] = "1중첩 추가"
L["Comma-separated spell IDs that grant stacks. Example: 190411,6343,435222 for Whirlwind, Thunder Clap, Thunder Blast"] = "중첩을 부여하는 주문 ID (쉼표로 구분). 예: 190411,6343,435222 (소용돌이, 천둥벼락, 천둥 질풍)"
-- 현재 프리셋 표시
L["Current Preset"] = "현재 적용"
L["Custom / None"] = "사용자 지정 / 없음"
-- 수동 추적 UI
L["Basic Settings"] = "기본 설정"
L["Trigger Spells (Generators)"] = "트리거 주문 (생성기)"
L["Consumer Spells (Spenders)"] = "소모기 주문 (소모기)"
L["Spells that generate stacks. Set 'Stacks' to the amount each spell adds (use max stacks value to set instantly to max)."] = "중첩을 생성하는 주문입니다. '중첩'을 각 주문이 추가하는 양으로 설정하세요 (최대 중첩 값 사용 시 즉시 최대로 설정)."
L["Spells that generate stacks. Click an icon below to add, or manually enter Spell ID."] = "중첩을 생성하는 주문입니다. 아래 아이콘을 클릭하여 추가하거나 직접 주문 ID를 입력하세요."
L["Spells that consume stacks. Set 'Consume' to the amount each spell uses."] = "중첩을 소모하는 주문입니다. '소모'를 각 주문이 사용하는 양으로 설정하세요."
L["Spells that consume stacks. Click an icon below to add, or manually enter Spell ID."] = "중첩을 소모하는 주문입니다. 아래 아이콘을 클릭하여 추가하거나 직접 주문 ID를 입력하세요."
L["Available Spells:"] = "사용 가능한 주문:"
L["No available spells for current spec"] = "현재 전문화에서 사용 가능한 주문이 없습니다"
L["Maximum 10 trigger spells allowed"] = "최대 10개의 트리거 주문만 허용됩니다"
L["Maximum 10 consumer spells allowed"] = "최대 10개의 소모기 주문만 허용됩니다"
L["Stacks to add when this spell is cast"] = "이 주문 시전 시 추가되는 중첩"
L["Stacks to consume when this spell is cast"] = "이 주문 시전 시 소모되는 중첩"
L["Add Trigger Spell"] = "트리거 주문 추가"
L["Add Consumer Spell"] = "소모기 주문 추가"
L["Remove this entry"] = "이 항목 제거"
L["Consume"] = "소모"
L["Empty"] = "비어있음"
L["Use Per-Spec Settings"] = "전문화별 설정 사용"
L["Use different trigger/consumer spells for each specialization"] = "각 전문화마다 다른 트리거/소모기 주문 사용"
L["Current Spec"] = "현재 전문화"
L["Choose what the bar fills based on: stack count or remaining duration"] = "바가 무엇을 기준으로 채워지는지 선택: 중첩 횟수 또는 남은 지속시간"
L["Bar Style"] = "바 스타일"
L["Bar Style Desc"] = "바의 시각적 스타일 선택"
L["Circular"] = "원형"
L["Square"] = "사각형"
L["Donut"] = "도넛"
L["Donut Thickness"] = "도넛 두께"
L["Donut Thickness Desc"] = "도넛 스타일의 링 두께를 조절합니다"
-- Talent Conditions
L["Talent Conditions"] = "특성 조건"
L["Configure talent-based conditions. The tracker can be enabled/disabled based on talents, or max stacks can be increased when specific talents are learned."] = "특성 기반 조건을 설정합니다. 특성에 따라 추적기를 활성화/비활성화하거나, 특정 특성을 배웠을 때 최대 중첩을 늘릴 수 있습니다."
L["Required Talent"] = "필수 특성"
L["Talent spell ID required to enable the tracker. Leave 0 or empty to always enable."] = "추적기를 활성화하기 위해 필요한 특성 주문 ID. 0이나 빈 칸으로 두면 항상 활성화됩니다."
L["Bonus Stacks Talent"] = "추가 중첩 특성"
L["Talent spell ID that grants bonus max stacks when learned. Leave 0 or empty to disable."] = "배웠을 때 추가 최대 중첩을 부여하는 특성 주문 ID. 0이나 빈 칸으로 두면 비활성화됩니다."
L["Bonus Stacks Amount"] = "추가 중첩량"
L["Additional max stacks when the bonus talent is learned"] = "추가 중첩 특성을 배웠을 때 늘어나는 최대 중첩"
L["Effective Max Stacks"] = "실제 최대 중첩"
L["Stacks Text Settings"] = "중첩 텍스트 설정"
L["Display remaining duration as text"] = "남은 지속시간을 텍스트로 표시"
L["Duration Text Size"] = "지속시간 텍스트 크기"
L["Duration Horizontal Offset"] = "지속시간 가로 위치"
L["Duration Vertical Offset"] = "지속시간 세로 위치"
L["Text Alignment"] = "텍스트 정렬"
L["Horizontal alignment of the text"] = "텍스트의 가로 정렬"
L["Duration Text Alignment"] = "지속시간 텍스트 정렬"
L["Horizontal alignment of the duration text"] = "지속시간 텍스트의 가로 정렬"
L["Click a preset to fill in the trigger and consumer spell values below."] = "프리셋을 클릭하면 아래 트리거/소모기 주문 값이 채워집니다."
L["Fill with Fury Warrior Whirlwind settings"] = "분노 전사 소용돌이 설정으로 채우기"
L["Fill with Havoc DH Momentum settings"] = "파멸 악사 갈무리한 기운 설정으로 채우기"
L["Fill with BM Hunter Frenzy settings"] = "야수 사냥꾼 광기 설정으로 채우기"
-- 버프 API 프리셋
L["Buff API Presets"] = "버프 API 프리셋"
L["These presets use Blizzard's buff API to track proc-based buffs."] = "이 프리셋들은 블리자드의 버프 API를 사용하여 발동 기반 버프를 추적합니다."
L["Enh Shaman - Maelstrom Weapon"] = "고양 주술 - 소용돌이치는 무기"
L["Track Maelstrom Weapon stacks (up to 10)"] = "소용돌이치는 무기 중첩 추적 (최대 10중첩)"
L["Enhancement Shaman Maelstrom Weapon preset applied!"] = "고양 주술사 소용돌이치는 무기 프리셋이 적용되었습니다!"
L["Arcane Mage - Clearcasting"] = "비전 마법사 - 번뜩임"
L["Track Clearcasting stacks (up to 3)"] = "번뜩임 중첩 추적 (최대 3중첩)"
L["Arcane Mage Clearcasting preset applied!"] = "비전 마법사 번뜩임 프리셋이 적용되었습니다!"
L["Demo Lock - Demonic Core"] = "악마학 흑마 - 악마의 핵"
L["Track Demonic Core stacks (up to 4)"] = "악마의 핵 중첩 추적 (최대 4중첩)"
L["Demonology Warlock Demonic Core preset applied!"] = "악마학 흑마법사 악마의 핵 프리셋이 적용되었습니다!"
L["WW Monk - Hit Combo"] = "풍운 수도사 - 타격 연계"
L["Track Hit Combo stacks (up to 6)"] = "타격 연계 중첩 추적 (최대 6중첩)"
L["Windwalker Monk Hit Combo preset applied!"] = "풍운 수도사 타격 연계 프리셋이 적용되었습니다!"
L["Fire Mage - Hot Streak"] = "화염 마법사 - 몰아치는 열기!"
L["Track Hot Streak duration"] = "몰아치는 열기! 지속시간 추적"
L["Fire Mage Hot Streak preset applied!"] = "화염 마법사 몰아치는 열기! 프리셋이 적용되었습니다!"
L["Shadow Priest - Shadowy Insight"] = "암흑 사제 - 어둠의 통찰"
L["Track Shadowy Insight proc"] = "어둠의 통찰 발동 추적"
L["Shadow Priest Shadowy Insight preset applied!"] = "암흑 사제 어둠의 통찰 프리셋이 적용되었습니다!"
-- 오라 카탈로그
L["Available Auras"] = "사용 가능한 오라"
L["click to select"] = "클릭하여 선택"
L["No available auras for current spec"] = "현재 전문화에서 사용 가능한 오라 없음"
-- CDM 통합
L["Scan CDM"] = "CDM 스캔"
L["Rescan Cooldown Manager frames to update the catalog"] = "카탈로그를 업데이트하기 위해 재사용 대기시간 매니저 프레임을 재스캔합니다"
-- Spell Cooldown Mode
-- Spell Bar v2.0
L["Ready"] = "준비"
-- Manual 추적 모드
L["Manual"] = "수동"
L["CDM mode uses Cooldown Manager integration for 100% accurate tracking. Manual mode tracks spell casts."] = "CDM 모드는 재사용 대기시간 매니저 연동으로 100% 정확한 추적을 제공합니다. 수동 모드는 주문 시전을 추적합니다."
L["No CDM entries found. Make sure Cooldown Manager is enabled."] = "CDM 항목을 찾을 수 없습니다. 재사용 대기시간 매니저가 활성화되어 있는지 확인하세요."
L["Spells that generate stacks"] = "중첩을 생성하는 주문"
L["Spells that consume stacks"] = "중첩을 소모하는 주문"
-- 트래킹 버프 UI (폴더블 리스트)
L["is already being tracked"] = "은(는) 이미 추적 중입니다"
-- Tracker Context Menu
L["Duration (sec)"] = "지속시간 (초)"
-- Per-bar position settings (Multi-bar system)
L["Hide Bar When Mana"] = "마나일 때 숨기기"
L["Border"] = "테두리"
L["Use different width/height when there is no secondary resource bar"] = "보조 자원 바가 없을 때 다른 너비/높이 사용"

-- ============================================================
-- CONFIG - ACTION BARS
-- ============================================================
L["Action Bars"] = "행동 단축바"
L["Action Bar Settings"] = "행동 단축바 설정"
L["Enable Action Bar Styling"] = "행동 단축바 스타일 적용"
L["Apply custom DDingUI styling to action bars"] = "행동 단축바에 띵UI 스타일 적용"
L["Border Thickness"] = "테두리 두께"
L["Thickness of the action button border (expands outward, WHITE8x8 texture)"] = "행동 버튼 테두리 두께 (바깥으로 확장)"
L["Backdrop Color"] = "배경 색상"
L["Color of the action button backdrop (using Blizzard's WHITE8x8 texture)"] = "행동 버튼 배경 색상"
L["Font Settings"] = "글꼴 설정"
L["Font used for action bar text elements. Leave as 'Use Global Font' to use the font from General settings."] = "행동 단축바 텍스트에 사용할 글꼴. '전역 글꼴 사용'으로 두면 일반 설정의 글꼴을 사용합니다."
L["Use Global Font"] = "전역 글꼴 사용"
L["Mouseover Settings"] = "마우스오버 설정"
L["Enable Mouseover"] = "마우스오버 활성화"
L["Action bars will fade out when not moused over. Use individual bar toggles below to select which bars use mouseover."] = "마우스를 올리지 않으면 행동 단축바가 투명해집니다. 아래 개별 토글로 적용할 바를 선택하세요."
L["Hidden Alpha"] = "숨김 투명도"
L["Alpha value for action bars when mouseover is enabled and not moused over"] = "마우스오버 활성화 시 마우스를 올리지 않았을 때의 투명도"
L["Individual Bar Mouseover"] = "개별 바 마우스오버"
L["Bar 1 (Main Action Bar)"] = "바 1 (주 행동 단축바)"
L["Enable mouseover for Bar 1"] = "바 1 마우스오버 활성화"

-- ============================================================
-- CONFIG - CAST BARS
-- ============================================================
L["Cast Bars"] = "시전 바"
L["Player Cast Bar"] = "플레이어 시전 바"
L["Target Cast Bar"] = "대상 시전 바"
L["Focus Cast Bar"] = "주시 대상 시전 바"
L["Boss Cast Bar"] = "우두머리 시전 바"
L["Swing Timer"] = "평타 타이머"
L["Swing Timer Bar"] = "평타 타이머 바"
L["Swing Timer Bar Settings"] = "평타 타이머 바 설정"
L["Enable Swing Timer Bar"] = "평타 타이머 바 활성화"
L["Show your auto-attack swing timer"] = "자동 공격 스윙 타이머를 표시합니다"
L["Main Hand Color"] = "주 무기 색상"
L["Off-Hand Color"] = "보조 무기 색상"
L["Show Off-Hand"] = "보조 무기 표시"
L["Show off-hand swing timer when dual-wielding"] = "쌍수일 때 보조 무기 스윙 타이머를 표시합니다"
L["Off-Hand Spacing"] = "보조 무기 간격"
L["Space between main-hand and off-hand bars"] = "주 무기와 보조 무기 바 사이의 간격"
L["Off-Hand Height"] = "보조 무기 높이"
L["Hide Out of Combat"] = "비전투 시 숨기기"
L["Hide the swing timer when not in combat"] = "전투 중이 아닐 때 스윙 타이머를 숨깁니다"
L["Idle Timeout"] = "유휴 시간"
L["Seconds after last swing before hiding the bar"] = "마지막 스윙 후 바를 숨기기까지의 시간(초)"
L["Number of decimal places for the timer text"] = "타이머 텍스트의 소수점 자릿수"
L["Text Font"] = "텍스트 글꼴"
L["Behavior"] = "동작"

-- ============================================================
-- CONFIG - VIEWER OPTIONS
-- ============================================================
L["Viewers"] = "아이콘 뷰어"
L["Essential Cooldowns"] = "핵심 능력"
L["Utility Cooldowns"] = "보조 능력"
L["Buff Icons"] = "강화 효과"
L["Buff Bar"] = "추적중인 막대"
L["Disable Dynamic Layout"] = "동적 레이아웃 비활성화"
L["Disable automatic bar positioning adjustments"] = "자동 바 위치 조정을 비활성화합니다"

-- ============================================================
-- CONFIG - UNIT FRAMES
-- ============================================================
L["Unit Frames"] = "유닛 프레임"
L["Frame"] = "프레임"
L["Frame width"] = "프레임 너비"
L["Frame height"] = "프레임 높이"
L["Positioning"] = "위치"
L["X Position"] = "X 위치"
L["Horizontal position of boss frames"] = "우두머리 프레임 가로 위치"
L["Y Position"] = "Y 위치"
L["Vertical position of boss frames"] = "우두머리 프레임 세로 위치"
L["Direction boss frames grow when multiple are shown"] = "여러 우두머리 프레임이 표시될 때 확장 방향"
L["Vertical spacing between boss frames"] = "우두머리 프레임 사이 세로 간격"
L["Boss Frame Positioning"] = "우두머리 프레임 위치"
L["Show/hide this unit frame"] = "이 유닛 프레임 표시/숨기기"
L["Show boss frames with fake data for testing layout and appearance"] = "레이아웃 테스트용 가짜 데이터로 우두머리 프레임 표시"
L["Color health bar by class color"] = "직업 색상으로 생명력 바 표시"
L["Health bar foreground color"] = "생명력 바 전경 색상"
L["Color health bar by reaction (hostile/neutral/friendly)"] = "반응별 생명력 바 색상 (적대/중립/우호)"
L["Health bar background color"] = "생명력 바 배경 색상"
L["Automatically anchor this frame to EssentialCooldownViewer. Only available for Player and Target frames."] = "이 프레임을 핵심 능력 뷰어에 자동 연결. 플레이어와 대상 프레임만 가능."
L["Frame name to anchor to (e.g., EssentialCooldownViewer, DDingUI_Player, DDingUI_Target, UIParent)"] = "연결할 프레임 이름 (예: EssentialCooldownViewer, DDingUI_Player, DDingUI_Target, UIParent)"
L["Anchor point on the frame"] = "프레임의 기준점"
L["Anchor point on parent"] = "부모의 기준점"
L["Horizontal offset from anchor"] = "기준점에서 가로 오프셋"
L["Vertical offset from anchor"] = "기준점에서 세로 오프셋"
L["Show the power bar (mana/energy/rage)"] = "자원 바 표시 (마나/기력/분노)"
L["Height of the power bar"] = "자원 바 높이"
L["Use default colors for power type (mana=blue, energy=yellow, etc.)"] = "자원 유형별 기본 색상 사용 (마나=파랑, 기력=노랑 등)"
L["Power bar foreground color"] = "자원 바 전경 색상"
L["Use power type color for background"] = "배경에 자원 유형 색상 사용"
L["Power bar background color"] = "자원 바 배경 색상"
L["Show unit name"] = "유닛 이름 표시"
L["Color name by class (player) or reaction (NPC)"] = "직업(플레이어) 또는 반응(NPC)별 이름 색상"
L["Custom name text color"] = "사용자 지정 이름 텍스트 색상"
L["Clamp displayed name length (0 = no limit)"] = "표시되는 이름 길이 제한 (0 = 제한 없음)"
L["Append target of target next to the target name without hiding the Target Target frame"] = "대상의 대상 프레임을 숨기지 않고 대상 이름 옆에 표시"
L["Separator shown between target and its target when inline is enabled"] = "인라인 활성화 시 대상과 대상의 대상 사이 구분자"
L["Show health text"] = "생명력 텍스트 표시"
L["Choose how health text is displayed"] = "생명력 텍스트 표시 방식 선택"
L["Text to use as separator between health numbers (e.g., ' - ', ' / ', ' | '). Only used when Display Style shows both current and percent."] = "생명력 숫자 사이 구분자 (예: ' - ', ' / ', ' | '). 현재값과 백분율 모두 표시할 때만 사용."
L["Health text color"] = "생명력 텍스트 색상"
L["Show power/resource text (mana, energy, etc.)"] = "자원 텍스트 표시 (마나, 기력 등)"
L["Choose how power text is displayed"] = "자원 텍스트 표시 방식 선택"
L["Power text color"] = "자원 텍스트 색상"
L["Display harmful debuffs applied by you"] = "내가 건 해로운 디버프 표시"
L["Show fake debuff icons to preview layout"] = "레이아웃 미리보기용 가짜 디버프 아이콘 표시"
L["Point on the frame where debuffs should anchor"] = "디버프가 연결될 프레임의 기준점"
L["Direction debuff icons grow within each row"] = "각 줄에서 디버프 아이콘이 확장되는 방향"
L["Direction rows grow relative to each other"] = "줄이 확장되는 방향"
L["Size of individual debuff icons"] = "개별 디버프 아이콘 크기"
L["Number of debuff icons to display per row"] = "줄당 표시할 디버프 아이콘 수"
L["Spacing between debuff icons"] = "디버프 아이콘 사이 간격"

-- ============================================================
-- CONFIG - PARTY/RAID FRAMES
-- ============================================================
L["Party Frames"] = "파티 프레임"
L["Raid Frames"] = "공격대 프레임"

-- ============================================================
-- CONFIG - CLICK CASTING
-- ============================================================
L["Click Casting"] = "클릭 시전"
L["Click-Casting Addon Conflict"] = "클릭 시전 애드온 충돌"
L["detected.\n\nWhich click-casting addon would you like to use?"] = "감지됨.\n\n어떤 클릭 시전 애드온을 사용하시겠습니까?"
L["Selecting an option will disable the other addon(s)\nand reload your UI."] = "선택하면 다른 애드온이 비활성화되고\nUI가 다시 로드됩니다."
L["Use DDingUI"] = "띵UI 사용"
L["Are you sure?"] = "정말 하시겠습니까?"
L["Having multiple click-casting addons enabled\nmay cause conflicts and unexpected behavior.\n\n|cffff6600Use at your own risk!|r"] = "여러 클릭 시전 애드온이 활성화되면\n충돌과 예기치 않은 동작이 발생할 수 있습니다.\n\n|cffff6600주의해서 사용하세요!|r"
L["This warning will not appear again after confirming."] = "확인 후에는 이 경고가 다시 표시되지 않습니다."
L["Go Back"] = "뒤로"
L["Confirm"] = "확인"
L["Left Click"] = "좌클릭"
L["Right Click"] = "우클릭"
L["Middle Click"] = "휠클릭"
L["Scroll Up"] = "휠 위로"
L["Scroll Down"] = "휠 아래로"
L["Target Unit"] = "유닛 대상 지정"
L["Unit Menu"] = "유닛 메뉴"
L["Set Focus"] = "주시 대상 설정"
L["Assist"] = "지원"
L["Mouseover"] = "마우스오버"
L["Self"] = "자신"
L["then"] = "후"
L["Unknown"] = "알 수 없음"
L["No Spell"] = "주문 없음"
L["Macro"] = "매크로"
L["Item"] = "아이템"
L["Slot"] = "슬롯"

-- ============================================================
-- MESSAGES & ERRORS
-- ============================================================
L["DDingUI: Import failed: No data found. Please paste your import string in the Import Profile String field."] = "띵UI: 가져오기 실패: 데이터를 찾을 수 없습니다. 프로필 문자열 가져오기 필드에 문자열을 붙여넣으세요."
L["DDingUI: Please enter a profile name for the imported profile."] = "띵UI: 가져올 프로필의 이름을 입력하세요."
L["DDingUI: Profile imported as '%s'. Please reload your UI."] = "띵UI: 프로필을 '%s'(으)로 가져왔습니다. UI를 다시 로드하세요."
L["DDingUI: Profile imported. Please reload your UI."] = "띵UI: 프로필을 가져왔습니다. UI를 다시 로드하세요."
L["DDingUI: Import failed: %s"] = "띵UI: 가져오기 실패: %s"
L["DDingUI: Invalid Import String."] = "띵UI: 잘못된 가져오기 문자열입니다."
L["No profile loaded."] = "프로필이 로드되지 않았습니다."
L["Export requires AceSerializer-3.0 and LibDeflate."] = "내보내기에는 AceSerializer-3.0과 LibDeflate가 필요합니다."
L["Failed to serialize profile."] = "프로필 직렬화에 실패했습니다."
L["Failed to compress profile."] = "프로필 압축에 실패했습니다."
L["Failed to encode profile."] = "프로필 인코딩에 실패했습니다."
L["Import requires AceSerializer-3.0 and LibDeflate."] = "가져오기에는 AceSerializer-3.0과 LibDeflate가 필요합니다."
L["No data provided."] = "데이터가 제공되지 않았습니다."
L["Could not decode string (maybe corrupted)."] = "문자열을 디코딩할 수 없습니다 (손상되었을 수 있음)."
L["Could not decompress data."] = "데이터를 압축 해제할 수 없습니다."
L["Could not deserialize profile."] = "프로필을 역직렬화할 수 없습니다."
L["Profile system not available."] = "프로필 시스템을 사용할 수 없습니다."
-- [REFACTOR] AceGUI → StyleLib: AceConfigDialog 폴백 제거됨
L["[DDingUI] Error: Custom GUI not loaded."] = "[띵UI] 오류: 커스텀 GUI가 로드되지 않았습니다."
L["[DDingUI] Party/Raid frames GUI not loaded."] = "[띵UI] 파티/공격대 프레임 GUI가 로드되지 않았습니다."

-- ============================================================
-- ALERT SYSTEM (BuffTracker)
-- ============================================================
L["Alert System"] = "알림 시스템"
L["Enable Alerts"] = "알림 활성화"
L["Active"] = "활성"
L["Inactive"] = "비활성"

-- ============================================================
-- ANCHOR POSITIONS
-- ============================================================
L["Select Frame"] = "프레임 선택"
L["Anchor Frame"] = "연결 대상"
L["Select Anchor"] = "앵커 지정"
L["No selection"] = "선택 없음"
L["Cannot anchor to self"] = "자기 자신에게 연결할 수 없습니다"

-- ============================================================
-- CONFIG - BUFF/DEBUFF FRAMES
-- ============================================================
L["Color of the stacks text"] = "중첩 텍스트 색상"
L["Color of the duration text"] = "지속시간 텍스트 색상"

-- ============================================================
-- CONFIG - UI SCALE & GENERAL
-- ============================================================
L["Apply Font to Blizzard UI"] = "블리자드 UI에 글꼴 적용"
L["Apply DDingUI font to Blizzard UI elements (buff durations, damage text, etc.). Disable if using ElvUI or other UI addons."] = "블리자드 UI 요소(버프 지속시간, 데미지 텍스트 등)에 띵UI 글꼴 적용. ElvUI 등 다른 UI 애드온 사용 시 비활성화하세요."
L["[DDingUI] Apply Font to Blizzard UI:"] = "[띵UI] 블리자드 UI에 글꼴 적용:"
L["Reload UI for full effect."] = "전체 효과를 위해 UI를 다시 로드하세요."

-- ============================================================
-- CONFIG - ADDITIONAL SETTINGS
-- ============================================================
L["Player"] = "플레이어"
L["Custom Icons"] = "커스텀 아이콘"

-- ============================================================
-- CONFIG - CAST BARS (DETAILED)
-- ============================================================
L["Center"] = "중앙"

-- ============================================================
-- CONFIG - VIEWER OPTIONS (DETAILED)
-- ============================================================
L["Settings"] = "설정"

-- ============================================================
-- CONFIG - RESOURCE BARS (DETAILED)
-- ============================================================
L["Hide the resource bar completely when current power is mana (prevents errors during druid shapeshifting)"] = "현재 자원이 마나일 때 자원 바 완전히 숨기기 (드루이드 변신 시 오류 방지)"
L["Hide the secondary bar entirely when the current power is mana"] = "현재 자원이 마나일 때 보조 바 완전히 숨기기"

-- ============================================================
-- CONFIG - RESOURCE BARS (ADVANCED COLOR OPTIONS)
-- ============================================================
L["Per-Segment Colors"] = "세그먼트별 색상"
L["Set individual colors for each rune/essence segment (1-6)"] = "각 룬/정수 세그먼트별 개별 색상 설정 (1-6)"
L["Reset all per-segment colors to default"] = "모든 세그먼트별 색상을 기본값으로 초기화"

-- ============================================================
-- CONFIG - RESOURCE BARS (HIDE WHEN MANA / NO PRIMARY SIZE)
-- ============================================================

-- ============================================================
-- CONFIG - PROFILES
-- ============================================================
L["Module Import"] = "모듈별 불러오기"
L["Import selected module settings from another specialization or profile.\nSelected module settings will overwrite the current profile."] = "다른 전문화 또는 프로필에서 특정 모듈 설정만 불러옵니다.\n선택한 모듈 설정이 현재 프로필에 덮어씌워집니다."
L["Import Source"] = "불러올 대상"
L["Another Specialization"] = "다른 전문화"
L["Another Profile"] = "다른 프로필"
L["Source Specialization"] = "원본 전문화"
L["Source Profile"] = "원본 프로필"
L["Modules to Import"] = "불러올 모듈 선택"
L["Select All"] = "전체 선택"
L["Clear All"] = "전체 해제"
L["Apply Import"] = "불러오기 적용"
L["Selected module settings will overwrite the current profile. Continue?"] = "선택한 모듈 설정을 현재 프로필에 덮어씌웁니다. 계속하시겠습니까?"
L["SpecProfiles module not found."] = "SpecProfiles 모듈을 찾을 수 없습니다."
L["Please select modules to import."] = "불러올 모듈을 선택해주세요."
L["Please select an import source."] = "원본을 선택해주세요."
L["Import complete: %s"] = "불러오기 완료: %s"
L["Import failed: source data not found."] = "불러오기 실패: 원본 데이터를 찾을 수 없습니다."
L["Default CDM Groups"] = "기본 CDM 그룹"
L["Dynamic Groups"] = "동적 그룹"
L["Shortcut Icons"] = "숏컷 아이콘"
L["Aura Tracker"] = "오라 트래커"
L["Buff Viewer"] = "강화효과 표시기"

-- ============================================================
-- CONFIG - DYNAMIC ICONS
-- ============================================================

-- ============================================================
-- CONFIG - GUI BUTTONS
-- ============================================================
L["Disable Anchors"] = "앵커 비활성화"
L["Hide draggable anchors for unit, party, and raid frames"] = "유닛, 파티, 공격대 프레임, 동적 아이콘의 드래그 앵커 숨기기"
L["Enable Anchors"] = "앵커 활성화"
L["Show draggable anchors for unit, party, raid frames, and action bars (works independently of Edit Mode)"] = "유닛, 파티, 공격대 프레임, 동적 아이콘의 드래그 앵커 표시 (편집 모드와 독립적)"
L["Open Advanced Cooldown Manager Panel"] = "고급 재사용 대기시간 관리자 패널 열기"
L["Open WoW's Edit Mode to reposition UI elements"] = "WoW 편집 모드를 열어 UI 요소 재배치"

-- ============================================================
-- CONFIG - BUFF BAR OPTIONS
-- ============================================================
L["Bar Spacing"] = "바 간격"
L["Space between bars"] = "바 사이 간격"
L["Icon Position"] = "아이콘 위치"
L["Where the icon sits relative to the bar"] = "바를 기준으로 아이콘을 배치할 위치"
L["Icon Left"] = "아이콘 왼쪽"
L["Icon Right"] = "아이콘 오른쪽"
L["Icon Gap"] = "아이콘 간격"
L["Space between the icon and the bar"] = "아이콘과 바 사이 간격"
L["Glow"] = "빛남"
L["Shine"] = "반짝임"

-- ============================================================
-- CONFIG - BUFF ICON VIEWER SPECIFIC (강화 효과)
-- ============================================================
L["Buff Duration Text Settings"] = "강화 효과 지속시간 텍스트 설정"
-- [12.0.1] 새 텍스트 옵션
L["Active Glow"] = "활성화 글로우"
L["Show glow effect when buff is active (alternative to swipe)"] = "버프 활성화 시 글로우 효과 표시 (스와이프 대체)"
L["Active Glow Type"] = "활성화 글로우 유형"
L["Type of glow effect to show when buff is active"] = "버프 활성화 시 표시할 글로우 효과 유형"
L["Active Glow Color"] = "활성화 글로우 색상"
L["Color of the active buff glow effect"] = "활성화된 버프 글로우 효과 색상"
L["Aura Glow Type"] = "오라 글로우 유형"
L["Aura Glow Color"] = "오라 글로우 색상"
L["Number of glow lines around the icon"] = "아이콘 주위에 표시되는 글로우 라인 수"
L["Animation speed of the pixel glow (lower = faster)"] = "픽셀 글로우 애니메이션 속도 (낮을수록 빠름)"
L["Thickness of the glow lines"] = "글로우 라인의 두께"
L["Length of the glow lines (0 = auto)"] = "글로우 라인의 길이 (0 = 자동)"

-- Personal Swipe Glow (생존기/쿨기 스와이프 글로우)

-- Icon Glow (Proc) (아이콘 글로우 - 프록)
L["Glow Type"] = "글로우 유형"
L["Glow Color"] = "글로우 색상"

-- ============================================================
-- CONFIG - ASSIST HIGHLIGHT (보조 강조 효과)
-- ============================================================

-- ============================================================
-- CONFIG - SPEC PROFILES (전문화별 프로필)
-- ============================================================
L["Spec Profiles"] = "전문화별 프로필"
L["Use Spec Profiles"] = "전문화별 설정"
L["Save/load settings per specialization automatically."] = "전문화 변경 시 설정 자동 저장/불러오기"
L["Settings are automatically saved when changing specs or every 30 seconds."] = "값이나 전문화를 변경하면 설정이 자동 저장됩니다."
L["Enable Spec Profiles"] = "전문화별 프로필 활성화"
L["Automatically save/load settings when changing specialization."] = "전문화 변경 시 설정을 자동으로 저장/불러옵니다."
L["Current Spec:"] = "현재 전문화:"
L["Save Now"] = "지금 저장"
L["Manually save current settings immediately."] = "현재 설정을 즉시 수동 저장합니다."
L["Revert to Saved"] = "저장된 설정으로 되돌리기"
L["Discard current changes and load saved settings."] = "현재 변경사항을 취소하고 저장된 설정을 불러옵니다."
L["Discard current changes and revert to saved settings?"] = "현재 변경사항을 취소하고 저장된 설정으로 되돌리시겠습니까?"
L["Delete Spec Profile"] = "전문화 프로필 삭제"
L["Are you sure you want to delete this spec profile?"] = "이 전문화 프로필을 삭제하시겠습니까?"
L["Global Settings"] = "글로벌 설정"
L["Save as Global"] = "글로벌로 저장"
L["Save current settings as the global (shared) preset."] = "현재 설정을 글로벌(공유) 프리셋으로 저장합니다."
L["Load from Global"] = "글로벌에서 불러오기"
L["Load the global (shared) settings. This will overwrite current settings."] = "글로벌(공유) 설정을 불러옵니다. 현재 설정이 덮어씌워집니다."
L["Load global settings? This will overwrite your current settings."] = "글로벌 설정을 불러오시겠습니까? 현재 설정이 덮어씌워집니다."
L["Copy Between Specs"] = "전문화 간 복사"
L["Copy From Spec"] = "다른 전문화에서 복사"
L["Copy settings from another spec to current. This will overwrite current settings."] = "다른 전문화의 설정을 현재로 복사합니다. 현재 설정이 덮어씌워집니다."
L["Copy settings from this spec? This will overwrite your current settings."] = "이 전문화의 설정을 복사하시겠습니까? 현재 설정이 덮어씌워집니다."
L["Saved Specs:"] = "저장된 전문화:"
L["spec profiles enabled."] = "전문화별 프로필이 활성화되었습니다."
L["settings saved for"] = "설정 저장됨:"
L["settings loaded for"] = "설정 불러옴:"
L["saved as global settings."] = "글로벌 설정으로 저장되었습니다."
L["global settings loaded."] = "글로벌 설정을 불러왔습니다."
L["settings copied from"] = "설정 복사함:"
L["to"] = "→"
L["spec profile deleted for"] = "전문화 프로필 삭제됨:"
L["Automatically switch the entire profile when you change specialization."] = "전문화 변경 시 전문화별 프로필을 자동으로 전환합니다."
L["Automatically switch the entire profile when you change specialization.\nEach spec can use a different profile with completely separate settings."] = "전문화 변경 시 프로필 전체를 자동으로 전환합니다.\n각 전문화마다 완전히 분리된 설정을 사용할 수 있습니다."
L["Profile per Specialization"] = "전문화별 프로필 지정"
L["Primary Power Bar"] = "주 자원 바"
L["Secondary Power Bar"] = "보조 자원 바"
L["Settings are automatically saved when changing values or specs."] = "값이나 전문화를 변경하면 설정이 자동 저장됩니다."

-- ============================================================
-- CONFIG - SOUND MODE (사운드 모드)
-- ============================================================
L["Custom Sound File"] = "커스텀 사운드 파일"
L["CustomSoundDesc"] = ".ogg, .mp3, .wav 파일 경로를 WoW 폴더 기준으로 입력하세요. 예: Interface\\AddOns\\DDingUI\\sounds\\alert.ogg\n설정하면 위의 사운드 선택보다 우선 적용됩니다."
L["Path to a custom sound file (e.g. Interface\\AddOns\\MyAddon\\alert.ogg). Supports .ogg, .mp3, .wav. Overrides the Sound selection above."] = "커스텀 사운드 파일 경로 (예: Interface\\AddOns\\MyAddon\\alert.ogg). .ogg, .mp3, .wav 지원. 위의 사운드 선택보다 우선 적용됩니다."
L["Interval Seconds"] = "주기 (초)"
L["Minimum Stacks"] = "최소 중첩"
L["Sound only plays when stacks >= this value"] = "이 값 이상의 중첩일 때만 사운드 재생"

-- ============================================================
-- CONFIG - THRESHOLD COLORS (임계값 색상)
-- ============================================================
L["Change bar color based on resource value"] = "자원 값에 따라 바 색상 변경"
L["Threshold Mode"] = "임계값 모드"
L["How to interpret threshold values"] = "임계값을 어떻게 해석할지"
L["Percent"] = "퍼센트"
L["Percentage"] = "퍼센트"
L["Absolute Value"] = "절대값"
L["Threshold 1 (Low Priority)"] = "임계값 1 (낮은 우선순위)"
L["Threshold 2 (Medium Priority)"] = "임계값 2 (중간 우선순위)"
L["Threshold 3 (High Priority)"] = "임계값 3 (높은 우선순위)"
L["When"] = "조건"

-- ============================================================
-- CONFIG - TEXT MODE (텍스트 모드)
-- ============================================================

-- ============================================================
-- CONFIG - ADVANCED ANIMATIONS (고급 애니메이션)
-- ============================================================
L["Pixel Glow"] = "픽셀 글로우"
L["Glow Color"] = "글로우 색상"

-- ============================================================
-- CONFIG - BUFF TRACKER NEW FEATURES (버프 추적기 신기능)
-- ============================================================
L["Auto-Detect"] = "자동 감지"
L["Detect max stacks and duration from active buff (must be active to detect)"] = "활성화된 버프에서 최대 중첩과 지속시간 감지 (버프가 활성화되어 있어야 감지 가능)"
L["Auto"] = "자동"
L["No cooldown ID found"] = "재사용 대기시간 ID를 찾을 수 없음"
L["Could not detect values. Is the buff active?"] = "값을 감지할 수 없습니다. 버프가 활성화되어 있나요?"
L["Auto-detected"] = "자동 감지됨"
L["No new values detected"] = "새 값이 감지되지 않음"

-- ============================================================
-- CONFIG - COOLDOWN TEXT FORMAT (v1.1.2)
-- ============================================================

-- ============================================================
-- CONFIG - FRAME PICKER (v1.1.2)
-- ============================================================

-- ============================================================
-- CONFIG - TEXTURE OPTIONS (v1.1.2)
-- ============================================================

-- ============================================================
-- CONFIG - CAST BAR INTERRUPTED FADE (v1.1.2)
-- ============================================================

-- ============================================================
-- CONFIG - FRAME PICKER BUTTON (v1.1.2)
-- ============================================================
L["Click on a frame to select it (ESC to cancel)"] = "프레임을 클릭하여 선택 (ESC로 취소)"
L["Frame selected:"] = "선택된 프레임:"

-- ============================================================
-- CONFIG - SECONDARY POWER BAR PERCENT OPTIONS (v1.1.2)
-- ============================================================

-- ============================================================
-- MOVER SYSTEM (v1.1.2)
-- ============================================================
L["Move Frames"] = "위치 조절"
L["Toggle frame mover mode to reposition DDingUI elements"] = "DDingUI 요소 위치 조절 모드 토글"
L["Primary Resource"] = "주 자원"
L["Secondary Resource"] = "보조 자원"
L["Player Cast Bar"] = "플레이어 시전바"
L["Target Cast Bar"] = "대상 시전바"
L["Focus Cast Bar"] = "주시대상 시전바"
L["Boss Cast Bar"] = "우두머리 시전바"
L["Buff Tracker Bar"] = "커스텀 오라 바"
L["Position Adjustment"] = "위치 조정"
L["No frame selected"] = "선택된 프레임 없음"
L["Left-click"] = "좌클릭: 드래그하여 이동"
L["Shift+Right-click"] = "Shift+우클릭: 위치 초기화"
L["Reset"] = "초기화"
L["Mover mode enabled"] = "위치 조절 모드 활성화됨. 프레임을 드래그하여 이동하세요."
L["Mover mode disabled"] = "위치 조절 모드 비활성화됨. 위치가 저장되었습니다."
L["Cannot toggle movers in combat"] = "전투 중에는 위치 조절 모드를 사용할 수 없습니다"
L["Anchor To"] = "연결 대상"
L["Select Anchor"] = "앵커 선택"
L["Grid"] = "격자"
L["Snap"] = "스냅"
L["Undo"] = "실행 취소"
L["Redo"] = "다시 실행"
L["Left-click: Change Anchor Point"] = "좌클릭: 앵커 포인트 변경"
L["Right-click: Change Self Point"] = "우클릭: 기준점 변경"
L["Done"] = "완료"
L["Buff Tracker Icon"] = "커스텀 오라 아이콘"
L["Buff Tracker Text"] = "커스텀 오라 텍스트"
L["Enable Group"] = "그룹 활성화"
L["Toggle this group on/off"] = "이 그룹 활성화/비활성화"
L["Left-click: Select and adjust"] = "좌클릭: 선택 및 조정"
L["Drag: Move frame"] = "드래그: 프레임 이동"
L["Right-click: Open settings"] = "우클릭: 설정 열기"
L["Shift+Right-click: Reset position"] = "Shift+우클릭: 위치 초기화"
L["Select a frame first"] = "먼저 프레임을 선택하세요"
L["Cannot anchor to self"] = "자기 자신에게 연결할 수 없습니다"
L["Show Grid"] = "격자 표시"
L["Enable Snap"] = "스냅 활성화"
L["Frames"] = "프레임"
L["Buff Tracker frames refreshed"] = "커스텀 오라 프레임 새로고침됨"
L["Enter mover mode first (/ddmove)"] = "먼저 이동 모드를 활성화하세요 (/ddmove)"

-- ============================================================
-- ICON CUSTOMIZATION (v1.1.5)
-- ============================================================
L["Scan Icons"] = "아이콘 스캔"
L["Click to select • Blue border = Customized"] = "클릭하여 선택 • 파란 테두리 = 커스터마이징됨"
L["Essential Cooldowns"] = "핵심 능력"
L["Utility Cooldowns"] = "보조 능력"
L["Buff Icons"] = "강화 효과"
L["Editing: %s"] = "편집 중: %s"
L["Deselect"] = "선택 해제"
L["Reset Icon"] = "아이콘 초기화"
L["Reset Glow"] = "글로우 초기화"
L["Ready State Glow"] = "상태 글로우"
L["Glow Type"] = "글로우 유형"
L["Action Button Glow"] = "행동 버튼 글로우"
L["Autocast Shine"] = "자동 시전 빛남"
L["Proc Effect"] = "발동 효과"
L["Glow Frequency"] = "글로우 속도"
L["Line Amount"] = "라인 수"
L["Line Thickness"] = "라인 두께"
L["Glow Trigger"] = "발동 조건"
L["When Ready (Cooldown)"] = "준비 완료 시 (재사용 대기시간)"
L["When Active (Buff)"] = "활성화 시 (버프)"
L["More Settings..."] = "세부 설정..."
L["Unassign"] = "할당 해제"
L["State Glow"] = "상태 글로우"
L["Icon State"] = "아이콘 상태"
L["Active State"] = "활성 상태"
L["Cooldown Swipe"] = "재사용 대기시간 스와이프"
L["Cooldown Edge"] = "재충전 테두리"
L["Cooldown Finish Flash"] = "재사용 완료 반짝임"
L["Active Duration Text"] = "활성 지속시간 텍스트"
L["Threshold Text"] = "임계값 텍스트"
L["Threshold Seconds"] = "임계값 시작 시간"
L["Threshold Decimals"] = "임계값 소수점"
L["Threshold Color"] = "임계값 색상"
L["Threshold Text Color"] = "임계값 텍스트 색상"
L["Always Show Buff"] = "비활성 시에도 표시"
L["Desaturate Inactive"] = "비활성 아이콘 채도"
L["Desaturate"] = "회색"
L["Full Color"] = "원래 색상"
L["Proc Glow"] = "발동 글로우"
L["Active State Glow"] = "활성 상태 글로우"
L["Max Charges Glow"] = "최대 충전 글로우"
L["Cooldown Ready Glow"] = "재사용 준비 글로우"
L["Glow Color Mode"] = "글로우 색상 방식"
L["Blizzard Glow"] = "블리자드 기본 글로우"
L["Keep Blizzard Default Glow Color"] = "블리자드 기본 글로우 색상 유지"
L["Custom Glow Color"] = "사용자 글로우 색상"
L["Custom"] = "사용자 지정"
L["Swipe Color"] = "스와이프 색상"
L["Class Color"] = "직업 색상"
L["Hide Active State"] = "활성 상태 숨기기"
L["Active Swipe Color"] = "활성 스와이프 색상"
L["Active Border"] = "활성 상태 테두리"
L["Active Border Color"] = "활성 테두리 색상"
L["Non Active State"] = "비활성 상태"
L["Desaturate When Not Active"] = "비활성 시 회색"
L["Cooldown State Effect"] = "재사용 대기 상태 효과"
L["Lower Alpha on Cooldown"] = "재사용 대기 중 투명도 낮춤"
L["Hidden on Cooldown"] = "재사용 대기 중 숨김"
L["Hidden When Ready"] = "사용 가능 시 숨김"
L["Cooldown State Opacity"] = "재사용 대기 투명도"
L["Charge Count"] = "충전 횟수"
L["Hide Recharge Swipe"] = "재충전 스와이프 숨기기"
L["Hide Recharge Edge"] = "재충전 테두리 숨기기"
L["Hide Duration With Charges"] = "충전 보유 시 시간 숨기기"
L["Charge Display"] = "충전 표시"
L["Audio on Buff Gain"] = "강화효과 획득 소리"
L["Audio on Buff Loss"] = "강화효과 종료 소리"
L["Audio Effect on Cooldown Ready"] = "재사용 준비 소리"
L["On"] = "켬"
L["None"] = "없음"
L["Default"] = "기본값"
L["Show"] = "표시"
L["Hide"] = "숨김"
L["Normal"] = "정방향"
L["Reverse"] = "역방향"
L["Hidden"] = "숨김"
L["Show Cooldown Swipe"] = "재사용 대기시간 스와이프 표시"
L["Show Charges"] = "충전 수 표시"
L["Desaturate on Cooldown"] = "재사용 대기시간 중 흑백 표시"
L["Desaturate When Unusable"] = "사용 불가 시 흑백 표시"
L["Hide When Empty"] = "보유하지 않을 때 숨기기"
L["Show Proc Duration"] = "발동 지속시간 표시"
L["Show Proc Stacks"] = "발동 중첩 표시"
L["Show Item Cooldown"] = "아이템 재사용 대기시간 표시"
L["Pixel Glow Settings"] = "픽셀 글로우 설정"
L["Group Assignment"] = "그룹 할당"
L["Off"] = "끔"
L["Ready"] = "준비"
L["Active"] = "활성"
L["Drag to reorder | Right-click for options"] = "드래그: 순서 변경 | 우클릭: 옵션"
L["Drag to reorder | Left-click for glow | Right-click for options"] = "드래그: 순서 변경 | 좌클릭: 글로우 | 우클릭: 옵션"
L["Drag to reorder | Right-click for options | Middle-click to unassign"] = "드래그: 순서 변경 | 우클릭: 옵션 | 가운데 클릭: 할당 해제"
L["Drag to reorder | Right-click for options | Middle-click to remove"] = "드래그: 순서 변경 | 우클릭: 옵션 | 가운데 클릭: 삭제"

-- ============================================================
-- BUFF TRACKER - BAR ORIENTATION & RING STYLE (v1.1.6)
-- ============================================================

-- ============================================================
-- DYNAMIC ICONS UI (v1.1.6)
-- ============================================================
L["Ungrouped"] = "미분류"
L["New Group"] = "새 그룹"
L["Delete \"%s\"?\nThis cannot be undone."] = "\"%s\" 삭제?\n이 작업은 되돌릴 수 없습니다."
L["Are you sure you want to delete group \"%s\"?\n\nAll icons in this group will be deleted.\nThis cannot be undone."] = "\"%s\" 그룹을 삭제하시겠습니까?\n\n이 그룹의 모든 아이콘이 삭제됩니다.\n이 작업은 되돌릴 수 없습니다."
L["Item"] = "아이템"
L["Spell"] = "주문"
L["Slot"] = "슬롯"

-- ============================================================
-- RING MODE OPTIONS (v1.1.6)
-- ============================================================
L["Ring Fill Mode"] = "링 채움 모드"
L["Show Text"] = "텍스트 표시"

-- ============================================================
-- MISSING ALERTS (v1.1.6)
-- ============================================================
L["Missing Alerts"] = "버프/펫 없음 알림"
L["Pet Missing"] = "펫 없음 알림"
L["Show alert when pet is missing (Hunter/Warlock/Unholy DK)"] = "펫이 없을 때 알림 표시 (사냥꾼/흑마/부정기사)"
L["Alert text to display"] = "표시할 알림 텍스트"
L["Class Buff Missing"] = "클래스 버프 없음 알림"
L["Show icon when your class buff is missing"] = "그룹 내 클래스 버프가 없는 멤버가 있으면 아이콘 표시"
L["Show icon when your class buff is missing (combat only)"] = "전투 중 그룹 내 클래스 버프가 없는 멤버가 있으면 아이콘 표시"
L["Desaturate"] = "흑백"
L["Show icon in grayscale"] = "아이콘을 흑백으로 표시"
L["Text Outline"] = "텍스트 외곽선"
L["Text Y Offset"] = "텍스트 Y 오프셋"
L["Vertical position of count text relative to icon"] = "아이콘 기준 텍스트 세로 위치"
L["Instance Only"] = "인스턴스 안에서만"
L["Only show pet alert inside instances (dungeons/raids/arenas/battlegrounds)"] = "인스턴스 안에서만 펫 알림 표시 (던전/레이드/투기장/전장)"
L["Display Conditions"] = "표시 조건"

-- ============================================================
-- BUFF TRACKER STACKING DIRECTION (v1.1.6)
-- ============================================================

-- ============================================================
-- FRAME STRATA SETTINGS
-- ============================================================

-- ============================================================
-- [GROUP SYSTEM] 그룹 시스템 옵션
-- ============================================================
L["Auto Classify"] = "자동 분류"
L["Automatically classify auras and cooldowns into groups"] = "오라와 재사용 대기시간을 자동으로 그룹에 분류"
L["Primary direction for icon placement"] = "아이콘 배치 주 방향"
L["Direction for row wrapping"] = "줄바꿈 방향"
L["Spell Assignment"] = "스펠 할당"
L["No manual assignments"] = "수동 할당 없음"
L["No manual assignments. Use grid or Spell ID to add."] = "수동 할당 없음. 아래 그리드 또는 스펠 이름으로 추가하세요."
L["No manual assignments. Use Quick Assign or Spell ID below."] = "수동 할당 없음. 아래의 빠른 할당이나 입력창을 이용하세요."
L["No manual assignments. Use Spell ID below."] = "수동 할당 없음. 아래 입력창을 이용하세요."
L["Click to unassign spell"] = "클릭시켜 스펠 할당 해제"
L["Click to unassign dynamic icon"] = "클릭시켜 동적 아이콘 할당 해제"
L["Drag to reorder | Click to remove"] = "드래그: 순서 변경 | 클릭: 삭제"
L["Drag to reorder | Right-click to remove"] = "드래그: 순서 변경 | 우클릭: 삭제"
L["Drag to reorder | Right-click to unassign"] = "드래그: 순서 변경 | 우클릭: 할당 해제"
L["Right-click to remove"] = "우클릭: 삭제"
L["Right-click to unassign"] = "우클릭: 할당 해제"
L["Clear All Assignments"] = "전체 할당 해제"
L["Remove all manual assignments for this group?"] = "이 그룹의 모든 수동 할당을 해제하시겠습니까?"
L["Enter Spell ID (number) or exact spell name. Buff spells auto-prefix buff_."] = "Spell ID(숫자) 또는 정확한 스펠 이름 입력. 버프 스펠은 자동으로 buff_ 접두사 추가."
L["Spell ID or Name"] = "Spell ID / 이름"
L["Quick Assign (Active Icons)"] = "빠른 할당 (활성 아이콘)"
L["Add Spell ID"] = "스펠 ID 추가"
L["Enter a spell ID to manually assign to this group"] = "이 그룹에 수동 할당할 스펠 ID를 입력하세요"
L["Add Spell Name"] = "스펠 이름 추가"
L["Enter a spell name to manually assign to this group. Use Ctrl+Click in edit mode for easier assignment."] = "이 그룹에 수동 할당할 스펠 이름을 입력하세요. 편집모드에서 Ctrl+Click으로 더 쉽게 할당할 수 있습니다."
L["Auto (Default)"] = "자동 (기본)"
L["Open Icon Grid"] = "아이콘 그리드 열기"
L["Visually assign CDM icons to this group"] = "CDM 아이콘을 시각적으로 이 그룹에 할당"
L["Click to assign, Shift+Click to remove"] = "클릭: 할당, Shift+클릭: 해제"
-- [DYNAMIC] Dynamic group options
L["Manage Icons"] = "아이콘 관리"
L["Open Custom Icons settings to add/remove dynamic icons"] = "커스텀 아이콘 설정을 열어 동적 아이콘 추가/삭제"
L["Active Icons"] = "활성 아이콘"
L["No active dynamic icons"] = "활성 동적 아이콘 없음"
L["This group displays icons from Custom Icons (consumables, healthstones, etc.). Use the button below to manage icons."] = "이 그룹은 커스텀 아이콘(생석/치물/물약 등)을 표시합니다. 아래 버튼으로 아이콘을 관리하세요."
L["Viewer Detail Settings"] = "뷰어 상세 설정"
L["Click: Assign to this group"] = "클릭: 이 그룹에 할당"
L["Shift+Click: Remove assignment"] = "Shift+클릭: 할당 해제"
L["Refresh"] = "새로고침"
L["Are you sure you want to delete this group?"] = "이 그룹을 삭제하시겠습니까?"
L["Settings"] = "설정"
L["Enter a spell name or numeric Spell ID to assign it to this group"] = "스펠 이름 또는 Spell ID를 입력하여 이 그룹에 할당"
L["Select category to filter available spells in Quick Assign"] = "빠른 할당에서 표시할 스킬 유형 선택"
L["Category"] = "분류"
L["Icon Movement Animation"] = "아이콘 이동 애니메이션"
-- [5TAB] GroupSystem 5탭 구조
L["Viewer"] = "뷰어"
L["No additional viewer settings available."] = "추가 뷰어 설정이 없습니다."
L["Icon Glow"] = "아이콘 글로우"
L["Viewer Anchor"] = "뷰어 앵커"
L["Frame Anchor"] = "프레임 고정"
L["Preview"] = "미리보기"
L["Keybind Text"] = "단축키 텍스트"
-- [12.0.1] GroupSystem 종횡비 + 아이템/장신구 추가 옵션
L["Enter an Item ID to add as a dynamic icon (e.g., trinket, potion)"] = "동적 아이콘으로 추가할 아이템 ID 입력 (예: 장신구, 물약)"
L["Trinket Buff Slot 1"] = "장신구 1 강화효과"
L["Trinket Buff Slot 2"] = "장신구 2 강화효과"

-- Buff Tracker WeakAuras-style Panel

-- Movers / NudgeFrame
L["Select Frame"] = "프레임 선택"
L["Show Grid"] = "그리드 표시"
L["Enable Snap"] = "스냅 활성화"
L["Buff Tracker frames refreshed"] = "커스텀 오라 프레임이 새로고침되었습니다"
L["Enter mover mode first (/ddmove)"] = "먼저 이동 모드를 활성화하세요 (/ddmove)"

-- Conditional Actions (Group Multi-Trigger)
L["Stacks ≥"] = "중첩 ≥"
L["Stacks ≤"] = "중첩 ≤"
L["Stacks ="] = "중첩 ="
L["Duration ≥"] = "지속시간 ≥"
L["Duration ≤"] = "지속시간 ≤"
L["Cooldown Ready"] = "재사용 대기시간 완료"
L["Cooldown Active"] = "재사용 대기시간 중"
L["Bar Color Change"] = "바 색상 변경"
L["Bar Glow"] = "바 글로우"
L["Icon Glow"] = "아이콘 글로우"
L["Icon Change"] = "아이콘 텍스처 변경"
L["Play Sound"] = "사운드 재생"
L["Show Text"] = "텍스트 알림"
L["Primary Power Bar"] = "주 자원 바"
L["Secondary Power Bar"] = "보조 자원 바"
L["Cast Bar"] = "시전 바"

-- Spell Cooldown Bar - Dynamic Labels

-- Group & Context Menu (GUI.lua)

-- Activation Condition (활성조건)

-- Quick Add (GroupSystemOptions.lua)

-- Hide Active State (Visual Effect)
L["Add Active Effect Overlay"] = "활성효과 오버레이 추가"
L["Active Effect Overlay (%s sec)"] = "활성효과 오버레이 (%s초)"
L["Change Active Effect Duration"] = "지속시간 변경"
L["Remove Active Effect Overlay"] = "활성효과 오버레이 제거"
L["Enter active effect duration (seconds):"] = "활성효과 지속시간(초)을 입력하세요:"
