--[[
    DDingToolKit - Korean Localization
    한국어 번역
]]

local L = LibStub("AceLocale-3.0"):NewLocale("DDingUI_Toolkit", "koKR")
if not L then return end

-- ==========================================
-- General / Common
-- ==========================================
L["ADDON_LOADED"] = "|cFF00FF00[DDingUI Toolkit]|r 로드 완료. /ddt 로 설정창을 엽니다."
L["ENABLED"] = "활성화"
L["DISABLED"] = "비활성화"
L["SETTINGS"] = "설정"
L["POSITION_RESET"] = "위치가 초기화되었습니다."
L["POSITION_LOCKED"] = "위치 잠금"
L["SCALE"] = "크기"
L["TEST_MODE"] = "테스트 모드"
L["TEST_ON_OFF"] = "테스트 ON/OFF"
L["RESET_POSITION"] = "위치 초기화"
L["MODULE_ENABLED"] = "모듈 활성화"
L["FONT"] = "글꼴"
L["FONT_SIZE"] = "글꼴 크기"
L["COLOR"] = "색상"
L["TEXT_COLOR"] = "텍스트 색상"
L["SHOW_TEXT"] = "텍스트 표시"
L["SIZE"] = "크기"
L["ICON_SIZE"] = "아이콘 크기"
L["OVERALL_SIZE"] = "전체 크기"
L["ALL_CHECK_ON"] = "모두 체크 ON"
L["ALL_CHECK_OFF"] = "모두 체크 OFF"

-- ==========================================
-- Main Frame / Tabs
-- ==========================================
L["TAB_GENERAL"] = "일반"
L["TAB_TALENTBG"] = "특성 배경"
L["TAB_LFGALERT"] = "파티 신청 알림"
L["TAB_MAILALERT"] = "우편 알림"
L["TAB_CURSORTRAIL"] = "커서 트레일"
L["TAB_ITEMLEVEL"] = "아이템 레벨"
L["TAB_NOTEPAD"] = "메모장"
L["TAB_COMBATTIMER"] = "전투 타이머"
L["TAB_PARTYTRACKER"] = "파티 트래커"
L["TAB_MYTHICPLUS"] = "쐐기 도우미"
L["TAB_GOLDSPLIT"] = "계산기"
L["TAB_DURABILITY"] = "내구도 체크"
L["TAB_BUFFCHECKER"] = "버프 체크"
L["TAB_KEYSTONETRACKER"] = "쐐기돌 추적"
L["TAB_CASTINGALERT"] = "타겟 스펠"
L["TAB_FOCUSINTERRUPT"] = "주시 차단"
L["TAB_SKYRIDINGTRACKER"] = "활공 트래커"


-- ==========================================
-- General Panel
-- ==========================================
L["MODULE_MANAGEMENT"] = "모듈 관리"
L["GLOBAL_SETTINGS"] = "전역 설정"
L["SHOW_MINIMAP_BUTTON"] = "미니맵 버튼 표시"
L["SHOW_WELCOME_MESSAGE"] = "로그인 시 환영 메시지"
L["MINIMAP_POSITION_RESET"] = "미니맵 버튼 위치가 초기화되었습니다."
L["MINIMAP_LEFT_CLICK"] = "클릭: 설정 열기"
L["MINIMAP_DRAG"] = "드래그: 버튼 이동"
L["INFO"] = "정보"
L["VERSION"] = "버전"
L["AUTHOR"] = "제작"

-- Module descriptions for General panel
L["MODULE_TALENTBG"] = "TalentBG - 특성창 배경 커스터마이저"
L["MODULE_LFGALERT"] = "파티 알림 - 파티 신청 알림"
L["MODULE_MAILALERT"] = "MailAlert - 새 메일 알림"
L["MODULE_CURSORTRAIL"] = "CursorTrail - 커서 트레일 효과"
L["MODULE_ITEMLEVEL"] = "ItemLevel - 아이템 레벨/인챈트/보석 표시"
L["MODULE_NOTEPAD"] = "Notepad - 파티 모집용 메모장"
L["MODULE_COMBATTIMER"] = "CombatTimer - 전투 타이머"
L["MODULE_PARTYTRACKER"] = "파티 상태 - 전투부활/영웅심/힐러마나"
L["MODULE_MYTHICPLUS"] = "MythicPlusHelper - 던전 텔레포트"
L["MODULE_GOLDSPLIT"] = "GoldSplit - 분배금 계산기"
L["MODULE_DURABILITY"] = "DurabilityCheck - 내구도 체크 알림"
L["MODULE_BUFFCHECKER"] = "BuffChecker - 버프 체크 (음식/영약/룬)"
L["MODULE_KEYSTONETRACKER"] = "KeystoneTracker - 파티 쐐기돌 추적"
L["MODULE_CASTINGALERT"] = "CastingAlert - 타겟 스펠 알림"
L["MODULE_FOCUSINTERRUPT"] = "FocusInterrupt - 주시 대상 차단바"
L["MODULE_SKYRIDINGTRACKER"] = "SkyridingTracker - 활공 비행 트래커"


-- ==========================================
-- CastingAlert Module
-- ==========================================
L["CASTINGALERT_DESC"] = "나를 대상으로 시전하는 적의 스킬 아이콘을 화면 중앙에 표시합니다.\n2개 이상 동시 시전 시 사운드 알림을 줄 수 있습니다."
L["CASTINGALERT_DISPLAY_SETTINGS"] = "표시 설정"
L["CASTINGALERT_SHOW_TARGET"] = "타겟 시전도 표시"
L["CASTINGALERT_ONLY_TARGETING_ME"] = "나를 대상으로 하는 스킬만 표시"
L["CASTINGALERT_MAX_SHOW"] = "최대 표시 수"
L["CASTINGALERT_DIM_ALPHA"] = "비대상 투명도"
L["CASTINGALERT_UPDATE_RATE"] = "갱신 주기 (초)"
L["CASTINGALERT_POSITION_SETTINGS"] = "위치 설정"
L["CASTINGALERT_POS_X"] = "가로 위치 (X)"
L["CASTINGALERT_POS_Y"] = "세로 위치 (Y)"
L["CASTINGALERT_SOUND_SETTINGS"] = "사운드 설정"
L["CASTINGALERT_SOUND_ENABLED"] = "동시 시전 사운드 알림"
L["CASTINGALERT_SOUND_THRESHOLD"] = "사운드 알림 기준 (N개 이상)"
L["CASTINGALERT_DEFAULT_SOUND"] = "레이드 경고 (기본)"
L["CASTINGALERT_TITLE"] = "시전 알림"
L["CASTINGALERT_DISABLE_FOR_TANK"] = "탱커 전문화일 때 비활성화"

-- ==========================================
-- FocusInterrupt Module
-- ==========================================
L["FOCUSINTERRUPT_DESC"] = "주시 대상이 시전할 때 시전바를 표시합니다.\n차단 준비 여부에 따라 색상이 변하고 차단 아이콘을 표시합니다."
L["FOCUSINTERRUPT_BAR_SETTINGS"] = "시전바 설정"
L["FOCUSINTERRUPT_BAR_WIDTH"] = "바 너비"
L["FOCUSINTERRUPT_BAR_HEIGHT"] = "바 높이"
L["FOCUSINTERRUPT_INT_SETTINGS"] = "차단 설정"
L["FOCUSINTERRUPT_NOTINT_HIDE"] = "차단 불가 시 숨김"
L["FOCUSINTERRUPT_CD_HIDE"] = "쿨다운 시 숨김"
L["FOCUSINTERRUPT_SHOW_KICK_ICON"] = "차단 아이콘 표시"
L["FOCUSINTERRUPT_SHOW_INTERRUPTER"] = "차단자 이름 표시"
L["FOCUSINTERRUPT_SHOW_TARGET"] = "시전 대상 표시"
L["FOCUSINTERRUPT_SHOW_TIME"] = "시전 시간 표시"
L["FOCUSINTERRUPT_MUTE"] = "사운드 끄기"
L["FOCUSINTERRUPT_FADE_TIME"] = "차단됨 페이드 시간"
L["FOCUSINTERRUPT_KICK_ICON_SIZE"] = "차단 아이콘 크기"
L["FOCUSINTERRUPT_COLOR_SETTINGS"] = "색상 설정"
L["FOCUSINTERRUPT_INTERRUPTIBLE_COLOR"] = "차단 가능"
L["FOCUSINTERRUPT_NOTINT_COLOR"] = "차단 불가"
L["FOCUSINTERRUPT_CD_COLOR"] = "쿨다운 중"
L["FOCUSINTERRUPT_INTERRUPTED_COLOR"] = "차단됨"
L["FOCUSINTERRUPT_INTERRUPTED"] = "차단됨"
L["FOCUSINTERRUPT_TEXTURE"] = "바 텍스쳐"
L["FOCUSINTERRUPT_DEFAULT_SOUND"] = "레이드 경고 (기본)"
L["FOCUSINTERRUPT_TITLE"] = "초점 차단"

-- ==========================================
-- BuffChecker Module
-- ==========================================
L["BUFFCHECKER_TITLE"] = "버프 체크"
L["BUFFCHECKER_DESC"] = "음식/영약/무기 인챈트/룬 버프가 없을 때 아이콘을 표시합니다.\n레이드나 쐐기 던전에서 버프 체크에 유용합니다."
L["BUFFCHECKER_CHECK_ITEMS"] = "체크 항목"
L["BUFFCHECKER_CHECK_FOOD"] = "음식 버프 체크"
L["BUFFCHECKER_CHECK_FLASK"] = "영약 버프 체크"
L["BUFFCHECKER_CHECK_WEAPON"] = "무기 인챈트 체크"
L["BUFFCHECKER_CHECK_RUNE"] = "룬 버프 체크"
L["BUFFCHECKER_DISPLAY_CONDITIONS"] = "표시 조건"
L["BUFFCHECKER_INSTANCE_ONLY"] = "인스턴스에서만 표시"
L["BUFFCHECKER_DISPLAY_SETTINGS"] = "화면 설정"
L["BUFFCHECKER_TEXT_SETTINGS"] = "텍스트 설정"
L["BUFFCHECKER_TEXT_FONT"] = "텍스트 글꼴"
L["BUFFCHECKER_FOOD"] = "음식"
L["BUFFCHECKER_FLASK"] = "영약"
L["BUFFCHECKER_MAINHAND"] = "주무기"
L["BUFFCHECKER_OFFHAND"] = "보조무기"
L["BUFFCHECKER_RUNE"] = "룬"

-- ==========================================
-- TalentBG Module
-- ==========================================
L["TALENTBG_TITLE"] = "특성창 배경"
L["TALENTBG_DESC"] = "특성창 배경 이미지를 커스터마이즈합니다."
L["TALENTBG_MODE"] = "배경 모드"
L["TALENTBG_MODE_SPEC"] = "전문화별"
L["TALENTBG_MODE_CLASS"] = "직업별"
L["TALENTBG_MODE_GLOBAL"] = "공용"
L["TALENTBG_SELECT_IMAGE"] = "이미지 선택"
L["TALENTBG_CURRENT_SPEC"] = "현재 전문화"
L["TALENTBG_PREVIEW"] = "미리보기"

-- ==========================================
-- LFGAlert Module
-- ==========================================
L["LFGALERT_TITLE"] = "파티 신청 알림"
L["LFGALERT_DESC"] = "누군가 파티에 신청하면 알림을 표시합니다."
L["LFGALERT_SOUND_ENABLED"] = "소리 알림"
L["LFGALERT_FLASH_ENABLED"] = "화면 깜빡임"
L["LFGALERT_SCREEN_ALERT"] = "화면 알림"
L["LFGALERT_CHAT_ALERT"] = "채팅 알림"
L["LFGALERT_AUTO_OPEN"] = "파티 찾기 자동 열기"
L["LFGALERT_LEADER_ONLY"] = "파티장만"
L["LFGALERT_SOUND_FILE"] = "알림 소리"
L["LFGALERT_SOUND_CHANNEL"] = "소리 채널"
L["LFGALERT_POSITION"] = "알림 위치"
L["LFGALERT_DURATION"] = "알림 지속시간"
L["LFGALERT_ANIMATION"] = "애니메이션"
L["LFGALERT_COOLDOWN"] = "쿨다운"
L["LFGALERT_DEFAULT_SOUND"] = "준비 완료 (기본)"
L["LFGALERT_NEW_APPLICATION"] = "새로운 파티 신청이 있습니다!"

-- ==========================================
-- MailAlert Module
-- ==========================================
L["MAILALERT_TITLE"] = "우편 알림"
L["MAILALERT_DESC"] = "새 우편이 도착하면 알림을 표시합니다."
L["MAILALERT_SOUND_ENABLED"] = "소리 알림"
L["MAILALERT_FLASH_ENABLED"] = "화면 깜빡임"
L["MAILALERT_SCREEN_ALERT"] = "화면 알림"
L["MAILALERT_CHAT_ALERT"] = "채팅 알림"
L["MAILALERT_HIDE_IN_COMBAT"] = "전투 중 숨기기"
L["MAILALERT_HIDE_IN_INSTANCE"] = "인스턴스에서 숨기기"
L["MAILALERT_NEW_MAIL"] = "새 우편이 도착했습니다!"

-- ==========================================
-- CursorTrail Module
-- ==========================================
L["CURSORTRAIL_TITLE"] = "커서 트레일"
L["CURSORTRAIL_DESC"] = "커서에 시각 효과를 추가합니다."
L["CURSORTRAIL_COLORS"] = "트레일 색상"
L["CURSORTRAIL_COLOR_COUNT"] = "색상 개수"
L["CURSORTRAIL_COLOR_FLOW"] = "색상 흐름"
L["CURSORTRAIL_FLOW_SPEED"] = "흐름 속도"
L["CURSORTRAIL_WIDTH"] = "트레일 너비"
L["CURSORTRAIL_HEIGHT"] = "트레일 높이"
L["CURSORTRAIL_ALPHA"] = "투명도"
L["CURSORTRAIL_TEXTURE"] = "텍스처"
L["CURSORTRAIL_BLEND_MODE"] = "블렌드 모드"
L["CURSORTRAIL_PRESETS"] = "프리셋"

-- ==========================================
-- ItemLevel Module
-- ==========================================
L["ITEMLEVEL_TITLE"] = "아이템 레벨 표시"
L["ITEMLEVEL_DESC"] = "가방과 캐릭터 창에서 장비의 아이템 레벨을 표시합니다."
L["ITEMLEVEL_SHOW_BAGS"] = "가방에서 표시"
L["ITEMLEVEL_SHOW_CHARACTER"] = "캐릭터 창에서 표시"
L["ITEMLEVEL_SHOW_INSPECT"] = "살펴보기에서 표시"
L["ITEMLEVEL_SHOW_QUALITY_COLOR"] = "품질 색상 사용"

-- ==========================================
-- Notepad Module
-- ==========================================
L["NOTEPAD_TITLE"] = "메모장"
L["NOTEPAD_DESC"] = "게임 내에서 간단한 메모를 작성합니다."
L["NOTEPAD_SAVE"] = "저장"
L["NOTEPAD_CLEAR"] = "지우기"
L["NOTEPAD_SAVED"] = "메모가 저장되었습니다!"
L["NOTEPAD_CLEARED"] = "메모가 삭제되었습니다!"

-- ==========================================
-- CombatTimer Module
-- ==========================================
L["COMBATTIMER_TITLE"] = "전투 타이머"
L["COMBATTIMER_DESC"] = "전투 경과 시간을 표시합니다."
L["COMBATTIMER_FORMAT"] = "시간 형식"
L["COMBATTIMER_SHOW_MS"] = "밀리초 표시"
L["COMBATTIMER_HIDE_OOC"] = "비전투 시 숨기기"

-- ==========================================
-- PartyTracker Module
-- ==========================================
L["PARTYTRACKER_TITLE"] = "파티 트래커"
L["PARTYTRACKER_DESC"] = "파티원의 능력과 쿨다운을 추적합니다."
L["PARTYTRACKER_TRACKED_SPELLS"] = "추적 주문"
L["PARTYTRACKER_ADD_SPELL"] = "주문 추가"
L["PARTYTRACKER_REMOVE_SPELL"] = "주문 제거"
L["PARTYTRACKER_BAR_TEXTURE"] = "바 텍스처"
L["PARTYTRACKER_BAR_WIDTH"] = "바 너비"
L["PARTYTRACKER_BAR_HEIGHT"] = "바 높이"
L["PARTYTRACKER_GROWTH_DIRECTION"] = "확장 방향"
L["PARTYTRACKER_SHOW_ICON"] = "아이콘 표시"
L["PARTYTRACKER_SHOW_NAME"] = "이름 표시"
L["PARTYTRACKER_SHOW_TIME"] = "시간 표시"

-- ==========================================
-- MythicPlusHelper Module
-- ==========================================
L["MYTHICPLUS_TITLE"] = "쐐기 도우미"
L["MYTHICPLUS_DESC"] = "쐐기 던전에 유용한 도구입니다."
L["MYTHICPLUS_DEATH_COUNTER"] = "사망 카운터"
L["MYTHICPLUS_TIMER"] = "타이머"
L["MYTHICPLUS_ENEMY_FORCES"] = "적 전력"

-- ==========================================
-- GoldSplit Module
-- ==========================================
L["GOLDSPLIT_TITLE"] = "골드 분배"
L["GOLDSPLIT_DESC"] = "버스 골드 분배를 계산합니다."
L["GOLDSPLIT_TOTAL_GOLD"] = "총 골드"
L["GOLDSPLIT_NUM_PLAYERS"] = "인원 수"
L["GOLDSPLIT_CALCULATE"] = "계산"
L["GOLDSPLIT_RESULT"] = "1인당: %s"
L["GOLDSPLIT_ANNOUNCE"] = "공지"
L["GOLDSPLIT_CHAT_TYPE"] = "채팅 종류"

-- ==========================================
-- DurabilityCheck Module
-- ==========================================
L["DURABILITY_TITLE"] = "내구도 체크"
L["DURABILITY_DESC"] = "장비 내구도가 낮을 때 알림을 표시합니다."
L["DURABILITY_THRESHOLD"] = "경고 기준"
L["DURABILITY_SOUND_ENABLED"] = "소리 알림"
L["DURABILITY_WARNING"] = "내구도가 낮습니다! (%d%%)"

-- ==========================================
-- Sound Channels
-- ==========================================
L["CHANNEL_MASTER"] = "마스터"
L["CHANNEL_SFX"] = "효과음"
L["CHANNEL_MUSIC"] = "음악"
L["CHANNEL_AMBIENCE"] = "환경음"
L["CHANNEL_DIALOG"] = "대화"

-- ==========================================
-- Positions
-- ==========================================
L["POS_TOP"] = "상단"
L["POS_BOTTOM"] = "하단"
L["POS_LEFT"] = "좌측"
L["POS_RIGHT"] = "우측"
L["POS_CENTER"] = "중앙"
L["POS_TOPLEFT"] = "좌상단"
L["POS_TOPRIGHT"] = "우상단"
L["POS_BOTTOMLEFT"] = "좌하단"
L["POS_BOTTOMRIGHT"] = "우하단"

-- ==========================================
-- Animations
-- ==========================================
L["ANIM_NONE"] = "없음"
L["ANIM_FADE"] = "페이드"
L["ANIM_SLIDE"] = "슬라이드"
L["ANIM_BOUNCE"] = "바운스"
L["ANIM_PULSE"] = "펄스"

-- ==========================================
-- Growth Directions
-- ==========================================
L["GROWTH_UP"] = "위로"
L["GROWTH_DOWN"] = "아래로"
L["GROWTH_LEFT"] = "왼쪽으로"
L["GROWTH_RIGHT"] = "오른쪽으로"

-- ==========================================
-- Common UI Elements
-- ==========================================
L["ADD"] = "추가"
L["APPLY"] = "적용"
L["CANCEL"] = "취소"
L["CLOSE"] = "닫기"
L["DELETE"] = "삭제"
L["EDIT"] = "수정"
L["SAVE"] = "저장"
L["NEW"] = "새로 만들기"
L["OPEN"] = "열기"
L["TEST"] = "테스트"
L["TEST_ALERT"] = "테스트 알림"
L["RESET_TO_DEFAULT"] = "기본값으로 복원"
L["ALERT_METHOD"] = "알림 방식"
L["SOUND_SETTINGS"] = "소리 설정"
L["SOUND_CUSTOM_PATH"] = "커스텀 경로 (mp3/ogg/wav)"
L["SOUND_TEST"] = "테스트"
L["COMBATTIMER_DEFAULT_SOUND"] = "기본 (카운트다운)"
L["SCREEN_ALERT_SETTINGS"] = "화면 알림 설정"
L["DISPLAY_SETTINGS"] = "표시 설정"
L["ALERT_POSITION"] = "알림 위치"
L["ALERT_SIZE"] = "알림 크기"
L["ALERT_COOLDOWN"] = "알림 쿨다운 (초)"
L["DISPLAY_DURATION"] = "표시 시간 (초)"
L["CONDITIONS"] = "조건"
L["ANIMATION"] = "애니메이션"
L["FLASH_TASKBAR"] = "화면 깜빡임 (작업표시줄)"
L["BACKGROUND"] = "배경"
L["BACKGROUND_ALPHA"] = "배경 투명도"
L["SHOW_BACKGROUND"] = "배경 표시"
L["LOCKED"] = "잠금"
L["UNLOCKED"] = "잠금 해제"
L["COMBAT_ONLY"] = "전투 중에만"
L["HIDE_IN_COMBAT"] = "전투 중 숨기기"
L["HIDE_IN_INSTANCE"] = "인스턴스에서 숨기기"
L["PRESET"] = "프리셋"
L["CUSTOM"] = "사용자 정의"
L["WIDTH"] = "너비"
L["HEIGHT"] = "높이"
L["TRANSPARENCY"] = "투명도"
L["TEXTURE"] = "텍스처"
L["LIFETIME"] = "수명"
L["MAX_COUNT"] = "최대 개수"
L["SPACING"] = "간격"
L["LAYER"] = "레이어"
L["TEXT_ALIGN"] = "텍스트 정렬"
L["ALIGN_LEFT"] = "왼쪽"
L["ALIGN_CENTER"] = "가운데"
L["ALIGN_RIGHT"] = "오른쪽"
L["USAGE"] = "사용법"
L["QUICK_ACCESS"] = "빠른 실행"
L["SAVED_NOTES"] = "저장된 메모"
L["SHOW_IN_PARTY"] = "파티에서 표시"
L["SHOW_IN_RAID"] = "레이드에서 표시"
L["MANA_BAR"] = "마나바"
L["MANA_TEXT"] = "마나 텍스트"
L["CHAT_SETTINGS"] = "채팅 설정"
L["CHAT_CHANNEL"] = "채팅 채널"
L["DEFAULT_CHAT_CHANNEL"] = "기본 채팅 채널"
L["THRESHOLD"] = "임계값"
L["TITLE_SIZE"] = "제목 크기"
L["PERCENT_SIZE"] = "퍼센트 크기"
L["SOUND_ON_START"] = "시작 시 소리"
L["PRINT_TO_CHAT"] = "채팅에 출력"
L["HIDE_DELAY"] = "숨김 지연"
L["COLOR_BY_TIME"] = "시간별 색상"
L["RELOAD_REQUIRED"] = "(리로드 필요)"
L["RELOAD_UI_CONFIRM"] = "이 변경사항은 UI 리로드가 필요합니다.\n지금 리로드 하시겠습니까?"
L["MODULE_DISABLED_MSG"] = "모듈이 비활성화되어 있습니다"
L["MODULE_DISABLED_HINT"] = "일반 탭에서 모듈을 활성화하세요"

-- ==========================================
-- TalentBG Extended
-- ==========================================
L["TALENTBG_SCOPE"] = "적용 범위"
L["TALENTBG_SELECT_BG"] = "배경 선택"
L["TALENTBG_ADD_BG"] = "배경 추가 (파일명만 입력)"
L["TALENTBG_DELETE_CONFIRM"] = "배경 '%s'을(를) 삭제하시겠습니까?"
L["TALENTBG_BG_DELETED"] = "배경 삭제됨: %s"
L["TALENTBG_BG_ADDED"] = "배경 추가됨: %s"
L["TALENTBG_BG_EXISTS"] = "이미 존재하는 배경입니다: %s"
L["TALENTBG_ENTER_FILENAME"] = "파일명을 입력하세요."
L["TALENTBG_APPLIED"] = "배경 적용됨 - %s"
L["TALENTBG_SELECT_TEXTURE"] = "텍스처를 선택하세요."
L["TALENTBG_NOT_IN_COMBAT"] = "전투 중에는 변경할 수 없습니다."
L["TALENTBG_RESET_CONFIRM"] = "기본 전문화 배경으로 복원하시겠습니까?\n\n|cFFFFFF00UI가 새로고침됩니다.|r"

-- ==========================================
-- LFGAlert Extended
-- ==========================================
L["LFGALERT_FLASH_DESC"] = "화면 깜빡임 (작업표시줄)"
L["LFGALERT_SCREEN_DESC"] = "화면 알림 표시"
L["LFGALERT_CHAT_DESC"] = "채팅창 알림"
L["LFGALERT_AUTO_OPEN_DESC"] = "자동으로 파티 찾기 창 열기"
L["LFGALERT_LEADER_ONLY_DESC"] = "파티장/부파티장만 알림 받기"
L["LFGALERT_TEST_MSG"] = "LFGAlert 테스트 알림!"
L["LFGALERT_NEW_APPLICANTS"] = "%d명의 신청자가 대기 중입니다."

-- ==========================================
-- MailAlert Extended
-- ==========================================
L["MAILALERT_CONDITION_SETTINGS"] = "조건 설정"
L["MAILALERT_HIDE_IN_COMBAT_DESC"] = "전투 중 알림 숨기기"
L["MAILALERT_HIDE_IN_INSTANCE_DESC"] = "던전/레이드 내 알림 숨기기"
L["MAILALERT_TEST_MSG"] = "MailAlert 테스트 알림!"
L["MAILALERT_NEW_MAIL_MSG"] = "새 메일이 도착했습니다!"

-- ==========================================
-- CursorTrail Extended
-- ==========================================
L["CURSORTRAIL_BASIC_SETTINGS"] = "기본 설정"
L["CURSORTRAIL_ENABLE"] = "커서 트레일 활성화"
L["CURSORTRAIL_COLOR_PRESETS"] = "색상 프리셋"
L["CURSORTRAIL_COLOR_SETTINGS"] = "색상 설정"
L["CURSORTRAIL_COLOR_NUM"] = "사용할 색상 개수"
L["CURSORTRAIL_COLOR_N"] = "색상 %d"
L["CURSORTRAIL_COLOR_FLOW_DESC"] = "색상 플로우 (무지개 효과)"
L["CURSORTRAIL_APPEARANCE"] = "외형"
L["CURSORTRAIL_PERFORMANCE"] = "성능 (FPS 영향)"
L["CURSORTRAIL_PERFORMANCE_WARNING"] = "|cffff6600주의: 수명이 길고 점이 많을수록 FPS가 감소합니다!|r"
L["CURSORTRAIL_DOT_LIFETIME"] = "점 수명 (초)"
L["CURSORTRAIL_MAX_DOTS"] = "최대 점 개수"
L["CURSORTRAIL_DOT_SPACING"] = "점 간격"
L["CURSORTRAIL_DISPLAY_CONDITIONS"] = "표시 조건"
L["CURSORTRAIL_COMBAT_ONLY"] = "전투 중에만 표시"
L["CURSORTRAIL_HIDE_INSTANCE"] = "던전/레이드 내 숨기기"
L["CURSORTRAIL_DISPLAY_LAYER"] = "표시 레이어"
L["CURSORTRAIL_BLEND_ADD"] = "글로우 (ADD)"
L["CURSORTRAIL_BLEND_BLEND"] = "불투명 (BLEND)"
L["CURSORTRAIL_LAYER_TOP"] = "최상단 (TOOLTIP)"
L["CURSORTRAIL_LAYER_BG"] = "배경 (BACKGROUND)"

-- ==========================================
-- ItemLevel Extended
-- ==========================================
L["ITEMLEVEL_DISPLAY_SETTINGS"] = "표시 설정"
L["ITEMLEVEL_SHOW_ILVL"] = "아이템 레벨 표시"
L["ITEMLEVEL_SHOW_ENCHANT"] = "인챈트 표시"
L["ITEMLEVEL_SHOW_GEMS"] = "보석 아이콘 표시"
L["ITEMLEVEL_SHOW_AVG"] = "평균 아이템 레벨 표시 (소수점 2자리)"
L["ITEMLEVEL_SHOW_ENHANCED"] = "강화 수치 상세 표시 (수치 + 퍼센트)"
L["ITEMLEVEL_SELF_SETTINGS"] = "본인 캐릭터 설정"
L["ITEMLEVEL_SELF_ILVL_SIZE"] = "아이템 레벨 글자 크기"
L["ITEMLEVEL_SELF_ENCHANT_SIZE"] = "인챈트 글자 크기"
L["ITEMLEVEL_SELF_GEM_SIZE"] = "보석 아이콘 크기"
L["ITEMLEVEL_SELF_AVG_SIZE"] = "평균 아이템 레벨 크기"
L["ITEMLEVEL_INSPECT_SETTINGS"] = "살펴보기 설정"
L["ITEMLEVEL_INSPECT_ILVL_SIZE"] = "아이템 레벨 글자 크기"
L["ITEMLEVEL_INSPECT_ENCHANT_SIZE"] = "인챈트 글자 크기"
L["ITEMLEVEL_INSPECT_GEM_SIZE"] = "보석 아이콘 크기"
L["ITEMLEVEL_RESET_MSG"] = "ItemLevel 설정이 초기화되었습니다."

-- ==========================================
-- Notepad Extended
-- ==========================================
L["NOTEPAD_BASIC_SETTINGS"] = "기본 설정"
L["NOTEPAD_SHOW_PVE_BUTTON"] = "파티 찾기(PVE) 창에 메모장 버튼 표시"
L["NOTEPAD_USAGE_TITLE"] = "사용법"
L["NOTEPAD_USAGE_TEXT"] = "|cFFFFFF001.|r 파티 찾기(PVE) 창 우측 상단의 '메모장' 버튼 클릭\n|cFFFFFF002.|r 또는 |cFF00CCFF/ddt notepad|r 명령어 입력\n|cFFFFFF003.|r '생성' 버튼으로 새 메모 추가\n|cFFFFFF004.|r 목록에서 메모 클릭하여 상세 보기/수정/삭제"
L["NOTEPAD_OPEN"] = "메모장 열기"
L["NOTEPAD_COUNT"] = "저장된 메모: %d개"
L["NOTEPAD_EMPTY"] = "저장된 메모가 없습니다."
L["NOTEPAD_NEW_MEMO"] = "새 메모"
L["NOTEPAD_MEMO_LIST"] = "메모 목록"
L["NOTEPAD_WRITE_MEMO"] = "메모 작성"
L["NOTEPAD_DETAIL_VIEW"] = "메모 상세보기"
L["NOTEPAD_MEMO_NAME"] = "메모 이름"
L["NOTEPAD_PARTY_NAME"] = "파티 이름"
L["NOTEPAD_DETAILS"] = "세부 정보"
L["NOTEPAD_DELETE_CONFIRM"] = "정말로 '%s' 메모를 삭제하시겠습니까?"
L["NOTEPAD_YES"] = "예"
L["NOTEPAD_NO"] = "아니오"

-- ==========================================
-- CombatTimer Extended
-- ==========================================
L["COMBATTIMER_DISPLAY_SETTINGS"] = "표시 설정"
L["COMBATTIMER_SHOW_MS"] = "밀리초 표시 (.XX)"
L["COMBATTIMER_SHOW_BG"] = "배경 표시"
L["COMBATTIMER_COLOR_BY_TIME"] = "시간대별 색상 변경 (30초/60초/120초)"
L["COMBATTIMER_FONT_SETTINGS"] = "글꼴 설정"
L["COMBATTIMER_ALERT_SETTINGS"] = "알림 설정"
L["COMBATTIMER_SOUND_ON_START"] = "전투 시작 시 소리"
L["COMBATTIMER_PRINT_TO_CHAT"] = "전투 종료 시 채팅에 시간 출력"
L["COMBATTIMER_TIMING_SETTINGS"] = "타이밍 설정"
L["COMBATTIMER_HIDE_DELAY"] = "종료 후 표시 유지 (초)"
L["COMBATTIMER_POSITION_RESET"] = "전투 타이머 위치가 초기화되었습니다."

-- ==========================================
-- PartyTracker Extended
-- ==========================================
L["PARTYTRACKER_MODULE_ENABLE"] = "모듈 활성화"
L["PARTYTRACKER_ENABLE_DESC"] = "PartyTracker 활성화 (리로드 필요)"
L["PARTYTRACKER_DISPLAY_SETTINGS"] = "표시 설정"
L["PARTYTRACKER_SHOW_PARTY"] = "파티에서 표시 (전투부활/영웅심/힐러마나)"
L["PARTYTRACKER_SHOW_RAID"] = "공격대에서 표시 (전투부활/영웅심/힐러마나)"
L["PARTYTRACKER_SHOW_LUST"] = "블러드 지속시간 및 쿨다운 표시"
L["PARTYTRACKER_SHOW_MANA_BAR"] = "힐러 마나바 표시"
L["PARTYTRACKER_SHOW_MANA_TEXT"] = "힐러 마나 퍼센트 텍스트 표시"
L["PARTYTRACKER_SIZE_SETTINGS"] = "크기 설정"
L["PARTYTRACKER_FONT_SETTINGS"] = "글꼴 설정"
L["PARTYTRACKER_MANA_BAR_SETTINGS"] = "힐러 마나바 설정"
L["PARTYTRACKER_MANA_BAR_WIDTH"] = "마나바 너비"
L["PARTYTRACKER_MANA_BAR_HEIGHT"] = "마나바 높이"
L["PARTYTRACKER_MANA_BAR_OFFSET_X"] = "마나바 X 오프셋"
L["PARTYTRACKER_MANA_BAR_OFFSET_Y"] = "마나바 Y 오프셋"
L["PARTYTRACKER_MANA_BAR_TEXTURE"] = "마나바 텍스쳐"
L["PARTYTRACKER_POSITION_RESET"] = "PartyTracker 위치가 초기화되었습니다."
L["PARTYTRACKER_MANA_POSITION_RESET"] = "마나 프레임 위치 초기화"
L["PARTYTRACKER_MANA_POSITION_RESET_MSG"] = "힐러 마나 프레임 위치가 초기화되었습니다."
L["PARTYTRACKER_SEPARATE_MANA"] = "힐러 마나 분리 표시"
L["PARTYTRACKER_SEPARATE_MANA_DESC"] = "힐러 마나를 별도 프레임으로 분리하여 표시"
L["PARTYTRACKER_MANA_LOCKED"] = "마나 프레임 위치 잠금"
L["PARTYTRACKER_MANA_SCALE"] = "마나 프레임 크기"
L["PARTYTRACKER_BREZ_LUST"] = "전투부활+영웅심"
L["PARTYTRACKER_HEALER_MANA"] = "힐러 마나"
L["PARTYTRACKER_INFO_TITLE"] = "트래커 정보"
L["PARTYTRACKER_INFO_TEXT"] = "|cFFFFFFFF파티 (5인)|r\n• 전투 부활 - 충전 수 & 쿨다운\n• 영웅심 - 버프/피로 상태\n• 힐러 마나 - 마나바 표시\n\n|cFFFFFFFF레이드|r\n• 전투 부활 - 충전 수 & 쿨다운\n• 힐러 마나 - 최대 6명\n\n|cFFFFFFFF표시 조건|r\n• 파티/레이드 참여 시 자동 표시\n• 드래그로 위치 이동 가능"
L["PARTYTRACKER_HEALERS_TITLE"] = "지원 힐러 직업"
L["PARTYTRACKER_HEALERS_TEXT"] = "• 회복 드루이드\n• 신성/수양 사제\n• 신성 성기사\n• 복원 주술사\n• 운무 수도사\n• 보존 기원사"

-- ==========================================
-- MythicPlusHelper Extended
-- ==========================================
L["MYTHICPLUS_TITLE_FULL"] = "신화+ 던전 도우미"
L["MYTHICPLUS_DESC_FULL"] = "신화+ 던전탭에서 던전 아이콘에 이름, 클리어 단수, 점수를 표시하고\n클릭 시 텔레포트를 시전합니다."
L["MYTHICPLUS_ENABLE_OVERLAY"] = "오버레이 활성화"
L["MYTHICPLUS_TEXT_SIZE"] = "텍스트 크기"
L["MYTHICPLUS_OPEN_TAB"] = "신화+ 던전탭 열기"
L["MYTHICPLUS_USAGE_TITLE"] = "사용법"
L["MYTHICPLUS_USAGE_TEXT"] = "- /ddt tp 명령어로 신화+ 던전탭을 엽니다\n- 던전 아이콘 위에 던전 이름 약어가 표시됩니다\n- 가운데 큰 숫자는 클리어한 최고 단수입니다\n- 아래 숫자는 해당 던전 점수입니다\n- 색상은 점수에 따라 변합니다 (흰색→녹색→파랑→보라→주황)\n- 던전 아이콘 클릭 시 텔레포트가 시전됩니다\n- 텔레포트는 해당 던전을 +20 이상 완료해야 배웁니다"

-- ==========================================
-- GoldSplit Extended
-- ==========================================
L["GOLDSPLIT_TITLE_FULL"] = "분배금 계산기"
L["GOLDSPLIT_DESC_FULL"] = "레이드 분배금을 계산하고 채팅으로 공유합니다.\n\n|cFFFFFF00슬래시 커맨드:|r /분배금, /goldsplit\n\n|cFFFFFF00기능:|r\n• 금액 입력 및 조정\n• N+1 분배 계산\n• 파티/레이드 채팅 자동 공유"
L["GOLDSPLIT_DEFAULT_CHANNEL"] = "기본 채팅 채널"
L["GOLDSPLIT_SAY"] = "말하기 (SAY)"
L["GOLDSPLIT_PARTY"] = "파티 (PARTY)"
L["GOLDSPLIT_RAID"] = "공격대 (RAID)"
L["GOLDSPLIT_NOTE"] = "|cFFFFFF00참고:|r 파티/레이드 중일 때는 자동으로 해당 채널로 전송됩니다."
L["GOLDSPLIT_POSITION_SETTINGS"] = "위치 설정"
L["GOLDSPLIT_POSITION_RESET_MSG"] = "창 위치가 초기화되었습니다."
L["GOLDSPLIT_DRAG_TIP"] = "|cFFFFFF00TIP:|r 계산기 창의 타이틀바를 드래그하여 위치를 이동할 수 있습니다."
L["GOLDSPLIT_OPEN_WINDOW"] = "계산기 창 열기"

-- ==========================================
-- DurabilityCheck Extended
-- ==========================================
L["DURABILITY_DESC_FULL"] = "내구도가 임계값 이하일 때 화면에 표시합니다.\n전투 중에는 자동으로 숨겨집니다.\n\n슬래시 커맨드: /내구도, /durability"
L["DURABILITY_DISPLAY_CONDITIONS"] = "표시 조건"
L["DURABILITY_THRESHOLD_DESC"] = "내구도 임계값 (%)"
L["DURABILITY_THRESHOLD_NOTE"] = "(이 값 이하일 때 화면에 표시)"
L["DURABILITY_ALERT_SETTINGS"] = "알림 설정"
L["DURABILITY_SOUND_DESC"] = "소리 알림 (임계값 도달 시)"
L["DURABILITY_SCREEN_SETTINGS"] = "화면 설정"
L["DURABILITY_POSITION_RESET_MSG"] = "내구도 알림 위치가 초기화되었습니다."
L["DURABILITY_DRAG_TIP"] = "|cFFFFFF00TIP:|r 알림 창을 드래그하여 위치를 이동할 수 있습니다."

-- ==========================================
-- Module Runtime Messages
-- ==========================================
-- CombatTimer
L["COMBATTIMER_TIME_RESULT"] = "전투 시간: %d:%05.2f"
L["COMBATTIMER_TEST_START"] = "전투 타이머 테스트 시작 (다시 클릭하면 종료)"

-- MailAlert
L["MAILALERT_TEST_MSG"] = "MailAlert 테스트 알림!"
L["MAILALERT_NEW_MAIL_ARRIVED"] = "새 메일이 도착했습니다!"

-- LFGAlert
L["LFGALERT_TEST_MSG"] = "LFGAlert 테스트 알림!"
L["LFGALERT_APPLICANTS_ARRIVED"] = "새로운 신청자가 %d명 도착했습니다!"

-- GoldSplit
L["GOLDSPLIT_RESET_DONE"] = "분배금이 초기화되었습니다."

-- MythicPlusHelper
L["MYTHICPLUS_ENABLED_MSG"] = "MythicPlusHelper 활성화됨 (신화+ 던전탭 개선)"

-- PartyTracker
L["PARTYTRACKER_TEST_END"] = "PartyTracker 테스트 모드 종료"
L["PARTYTRACKER_TEST_START"] = "PartyTracker 테스트 모드 (다시 클릭하면 종료)"
L["PARTYTRACKER_COMMANDS"] = "명령어:"
L["PARTYTRACKER_SETTINGS_NOT_FOUND"] = "설정을 찾을 수 없습니다."
L["PARTYTRACKER_MODULE_ENABLED_MSG"] = "모듈 |cFF00FF00활성화|r (리로드 필요: /reload)"
L["PARTYTRACKER_MODULE_DISABLED_MSG"] = "모듈 |cFFFF0000비활성화|r (리로드 필요: /reload)"
L["PARTYTRACKER_PARTY_DISPLAY"] = "파티 표시:"
L["PARTYTRACKER_RAID_DISPLAY"] = "레이드 표시:"
L["PARTYTRACKER_MANA_BAR_DISPLAY"] = "마나바 표시:"
L["PARTYTRACKER_MANA_TEXT_DISPLAY"] = "마나 텍스트 표시:"
L["PARTYTRACKER_CURRENT_SETTINGS"] = "현재 설정:"
L["PARTYTRACKER_MODULE_ACTIVE"] = "모듈 활성화:"
L["PARTYTRACKER_ALL_ENABLED"] = "모든 옵션 |cFF00FF00활성화|r (리로드 필요: /reload)"
L["PARTYTRACKER_UNKNOWN_CMD"] = "알 수 없는 명령어. /pt help 로 도움말 확인"
L["PARTYTRACKER_ON"] = "|cFF00FF00ON|r"
L["PARTYTRACKER_OFF"] = "|cFFFF0000OFF|r"

-- DurabilityCheck
L["DURABILITY_CHECK_MSG"] = "내구도 체크: %d%%"

-- KeystoneTracker
L["KEYSTONETRACKER_ENABLED"] = "KeystoneTracker 활성화됨. /ddt keys 로 열기"
L["KEYSTONETRACKER_PARTY_KEYS"] = "파티 쐐기돌"
L["KEYSTONETRACKER_NO_KEY"] = "쐐기돌 없음"
L["KEYSTONETRACKER_NO_INFO"] = "정보 없음"

-- KeystoneTracker Config
L["KEYSTONETRACKER_TITLE"] = "쐐기돌 추적"
L["KEYSTONETRACKER_DESC"] = "파티원들의 쐐기돌 정보를 추적하고 공유합니다."
L["KEYSTONETRACKER_SHOW_IN_PARTY"] = "파티에서 표시"
L["KEYSTONETRACKER_SHOW_IN_RAID"] = "레이드에서 표시"
L["KEYSTONETRACKER_TOGGLE_WINDOW"] = "창 열기/닫기"
L["KEYSTONETRACKER_USAGE_TITLE"] = "|cFFFFD100사용법:|r"
L["KEYSTONETRACKER_USAGE_TEXT"] = "- 파티에 참여하면 자동으로 쐐기돌 정보를 교환합니다\n- DDingToolKit 사용자끼리 자동으로 정보가 공유됩니다\n- /dding keys 명령어로 창을 열 수 있습니다"

-- ==========================================
-- Additional Runtime Messages
-- ==========================================
-- MailAlert frame text
L["MAILALERT_NEW_MAIL_TEXT"] = "새 메일이 도착했습니다!"
L["MAILALERT_TEST_TEXT"] = "테스트 알림!"

-- LFGAlert frame text
L["LFGALERT_NEW_APPLICANT_TITLE"] = "새로운 신청자!"
L["LFGALERT_TEST_TEXT"] = "테스트 알림!"
L["LFGALERT_WORKING_PROPERLY"] = "LFGAlert가 정상 작동합니다."
L["LFGALERT_WAITING_COUNT"] = "%d명의 신청자가 대기 중입니다."

-- GoldSplit UI
L["GOLDSPLIT_TOTAL_GOLD"] = "총 골드"
L["GOLDSPLIT_MANUAL_INPUT"] = "금액 직접 입력"
L["GOLDSPLIT_ADJUST_AMOUNT"] = "분배금 조정 (+/-)"
L["GOLDSPLIT_CALCULATE_SHARE"] = "분배금 계산 및 공유"
L["GOLDSPLIT_RESET"] = "초기화"
L["GOLDSPLIT_RESET_CONFIRM"] = "분배금을 초기화하시겠습니까?"
L["GOLDSPLIT_CONFIRM"] = "확인"
L["GOLDSPLIT_CANCEL"] = "취소"
L["GOLDSPLIT_INPUT_TITLE"] = "금액 입력"
L["GOLDSPLIT_ADJUST_TITLE"] = "분배금 조정"
L["GOLDSPLIT_CALC_TITLE"] = "분배금 계산"
L["GOLDSPLIT_SPLIT_PLAYERS"] = "분배 인원:"
L["GOLDSPLIT_PREVIEW_FORMAT"] = "인당: %sG | 파티당: %sG"
L["GOLDSPLIT_SHARE_CHAT"] = "채팅 공유"

-- AutoRepair
L["TAB_AUTOREPAIR"] = "자동 수리"
L["MODULE_AUTOREPAIR"] = "자동수리"
L["AUTOREPAIR_TITLE"] = "자동수리"
L["AUTOREPAIR_DESC"] = "상인 방문 시 장비를 자동으로 수리합니다."
L["AUTOREPAIR_USE_GUILD_BANK"] = "길드 금고로 수리"
L["AUTOREPAIR_GUILD_BANK_NOTE"] = "길드 금고를 먼저 사용합니다. 불가능하면 개인 골드로 수리합니다."
L["AUTOREPAIR_CHAT_OUTPUT"] = "수리 비용 채팅 출력"
L["AUTOREPAIR_REPAIRED"] = "장비 수리 완료"
L["AUTOREPAIR_GUILD_BANK"] = "길드 금고"
L["AUTOREPAIR_PERSONAL_GOLD"] = "개인 골드"

-- DurabilityCheck
L["DURABILITY_REPAIR_NEEDED"] = "수리 필요"

-- SkyridingTracker
L["SKYRIDINGTRACKER_TITLE"] = "활공 트래커"
L["SKYRIDINGTRACKER_DESC"] = "활공 비행 시 기력, 활력, 소용돌이 쇄도 쿨타임을 직관적인 HUD로 표시합니다."
L["SKYRIDINGTRACKER_ONLY_MOUNTED"] = "탑승 중에만 표시"
L["SKYRIDINGTRACKER_HIDE_WHEN_FULL"] = "꽉 차면 숨기기"
L["SKYRIDINGTRACKER_HIDE_WHEN_FULL"] = "꽉 차면 숨기기"
L["SKYRIDINGTRACKER_FADEOUT"] = "페이드 아웃 시간 (초)"
L["SKYRIDINGTRACKER_SURGE_POS"] = "소용돌이 쇄도 위치"
L["SKYRIDINGTRACKER_SURGE_BOTTOM"] = "하단"
L["SKYRIDINGTRACKER_SURGE_TOP"] = "상단"
L["SKYRIDINGTRACKER_BORDER"] = "테두리 크기"
L["SKYRIDINGTRACKER_POS_X"] = "X 위치"
L["SKYRIDINGTRACKER_POS_Y"] = "Y 위치"
L["SKYRIDINGTRACKER_HIDE_DDINGUI"] = "DDingUI 요소 숨기기"
L["SKYRIDINGTRACKER_HIDE_DDINGUI_DESC"] = "비행 중 DDingUI UF, CDM, Essential 프레임을 숨깁니다."
L["SKYRIDINGTRACKER_HIDE_OUTSIDE_ONLY"] = "인스턴스 밖에서만 숨기기"
L["SKYRIDINGTRACKER_POSITION_RESET_MSG"] = "트래커 위치가 초기화되었습니다."
L["SKYRIDINGTRACKER_INFO_TITLE"] = "트래커 구조"
L["SKYRIDINGTRACKER_INFO_TEXT"] = "• |cFF00CCFF좌측 C모양:|r 활공 비행 기력 (최대 6회)\n• |cFF00FF00우측 역C모양:|r 재기의 바람 충전 횟수 (최대 3회)\n• |cFFFF8800하단 C커브:|r 소용돌이 쇄도 쿨타임 바"
L["SKYRIDINGTRACKER_COLOR_VIGOR"] = "기력 색상"
L["SKYRIDINGTRACKER_COLOR_VIGOR_ACTIVE"] = "기력 (활성)"
L["SKYRIDINGTRACKER_COLOR_VIGOR_DIM"] = "기력 (비활성)"
L["SKYRIDINGTRACKER_COLOR_WIND"] = "재기의 바람 색상"
L["SKYRIDINGTRACKER_COLOR_WIND_ACTIVE"] = "재기의 바람 (활성)"
L["SKYRIDINGTRACKER_COLOR_WIND_DIM"] = "재기의 바람 (비활성)"
L["SKYRIDINGTRACKER_COLOR_SURGE"] = "소용돌이 쇄도 색상"
L["SKYRIDINGTRACKER_COLOR_SURGE_ACTIVE"] = "소용돌이 쇄도 (활성)"
L["SKYRIDINGTRACKER_COLOR_SURGE_DIM"] = "소용돌이 쇄도 (비활성)"

-- MythicPlusHelper tooltips

L["MYTHICPLUS_NO_TELEPORT_INFO"] = "텔레포트 스펠 정보 없음"
L["MYTHICPLUS_NOT_LEARNED"] = "아직 배우지 않음 (+20 클리어 필요)"
L["MYTHICPLUS_AVAILABLE"] = "사용 가능"
L["MYTHICPLUS_WEEKLY_COUNT"] = "이번주 쐐기 횟수: %d"
