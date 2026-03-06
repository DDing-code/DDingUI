local L = LibStub("AceLocale-3.0"):NewLocale("DDingUI_UF", "koKR")
if not L then return end

------------------------------------------------------------------------
-- UNIT NAMES
------------------------------------------------------------------------
L["UNIT_PLAYER"]           = "플레이어"
L["UNIT_TARGET"]           = "대상"
L["UNIT_TARGETTARGET"]     = "대상의 대상"
L["UNIT_FOCUS"]            = "주시 대상"
L["UNIT_FOCUSTARGET"]      = "주시 대상의 대상"
L["UNIT_PET"]              = "소환수"
L["UNIT_BOSS"]             = "우두머리"
L["UNIT_ARENA"]            = "투기장"
L["UNIT_PARTY"]            = "파티"
L["UNIT_RAID"]             = "공격대"
L["UNIT_PARTY_COUNT"]      = "파티 (5인)"
L["UNIT_RAID_COUNT"]       = "공격대 (20인)"

------------------------------------------------------------------------
-- WIDGET NAMES
------------------------------------------------------------------------
L["WIDGET_NAME"]           = "이름"
L["WIDGET_HEALTH_TEXT"]    = "체력 텍스트"
L["WIDGET_POWER_TEXT"]     = "자원 텍스트"
L["WIDGET_LEVEL_TEXT"]     = "레벨 텍스트"
L["WIDGET_CUSTOM_TEXT"]    = "사용자 정의 텍스트"
L["WIDGET_BUFFS"]          = "버프"
L["WIDGET_DEBUFFS"]        = "디버프"
L["WIDGET_DISPELS"]        = "해제"
L["WIDGET_RAID_ICON"]      = "공격대 아이콘"
L["WIDGET_ROLE_ICON"]      = "역할 아이콘"
L["WIDGET_LEADER_ICON"]    = "파티장 아이콘"
L["WIDGET_COMBAT_ICON"]    = "전투 아이콘"
L["WIDGET_READY_CHECK"]    = "준비 확인"
L["WIDGET_RESTING_ICON"]   = "휴식 아이콘"
L["WIDGET_RESURRECT_ICON"] = "부활 아이콘"
L["WIDGET_SUMMON_ICON"]    = "소환 아이콘"
L["WIDGET_SHIELD_BAR"]     = "보호막 바"
L["WIDGET_CAST_BAR"]       = "시전바"
L["WIDGET_CLASS_BAR"]      = "직업 자원"
L["WIDGET_ALT_POWER_BAR"]  = "대체 자원 바"
L["WIDGET_POWER_BAR"]      = "자원 바"
L["WIDGET_HEAL_PREDICTION"] = "치유 예측"
L["WIDGET_HEAL_ABSORB"]    = "치유 흡수"
L["WIDGET_FADER"]          = "페이드"
L["WIDGET_HIGHLIGHT"]      = "하이라이트"
L["WIDGET_THREAT"]         = "위협"

------------------------------------------------------------------------
-- TEXTURE / FONT FALLBACK
------------------------------------------------------------------------
L["TEXTURE_FLAT_DEFAULT"]  = "단색 (기본)"
L["FONT_DEFAULT"]          = "기본 글꼴"
L["FONT_BOLD"]             = "굵은 글꼴"

------------------------------------------------------------------------
-- ORIENTATION LIST
------------------------------------------------------------------------
L["ORIENT_LEFT_RIGHT"]     = "왼→오"
L["ORIENT_RIGHT_LEFT"]     = "오→왼"
L["ORIENT_TOP_BOTTOM"]     = "위→아래"
L["ORIENT_BOTTOM_TOP"]     = "아래→위"

------------------------------------------------------------------------
-- HEALTH FORMAT LIST
------------------------------------------------------------------------
L["FMT_PERCENTAGE"]        = "퍼센트"
L["FMT_CURRENT"]           = "현재값"
L["FMT_CURRENT_MAX"]       = "현재/최대"
L["FMT_DEFICIT"]           = "손실량"
L["FMT_CURRENT_PERCENT"]   = "현재 (퍼센트)"
L["FMT_PERCENT_CURRENT"]   = "퍼센트 | 현재값"
L["FMT_CURRENT_PERCENT2"]  = "현재값 | 퍼센트"

------------------------------------------------------------------------
-- POWER FORMAT LIST (additional)
------------------------------------------------------------------------
L["FMT_SMART"]             = "스마트"
L["FMT_CURRENT_PERCENT3"]  = "현재(퍼센트)"
L["FMT_PERCENT_SLASH_CUR"] = "퍼센트/현재"
L["FMT_CUR_SLASH_PERCENT"] = "현재/퍼센트"

------------------------------------------------------------------------
-- NAME FORMAT LIST
------------------------------------------------------------------------
L["NAME_FMT_NAME"]         = "이름"
L["NAME_FMT_ABBREV"]       = "이름 (약어)"
L["NAME_FMT_SHORT"]        = "이름 (짧게)"

------------------------------------------------------------------------
-- CATEGORY TREE (top-level)
------------------------------------------------------------------------
L["CAT_GENERAL"]           = "일반"
L["CAT_GLOBAL_SETTINGS"]   = "전역 설정"
L["CAT_MEDIA"]             = "미디어"
L["CAT_COLORS"]            = "색상"
L["CAT_MODULES"]           = "모듈"
L["CAT_PROFILES"]          = "프로필"
L["CAT_UNIT_FRAMES"]       = "유닛 프레임"
L["CAT_GROUP_FRAMES"]      = "그룹 프레임"
L["CAT_ENEMY_FRAMES"]      = "적 프레임"

------------------------------------------------------------------------
-- SUBCATEGORY NAMES
------------------------------------------------------------------------
L["SUBCAT_GENERAL"]        = "기본"
L["SUBCAT_HEALTH"]         = "체력바"
L["SUBCAT_POWER"]          = "자원 바"
L["SUBCAT_CASTBAR"]        = "시전바"
L["SUBCAT_CLASSBAR"]       = "직업 자원"
L["SUBCAT_BUFFS"]          = "버프"
L["SUBCAT_DEBUFFS"]        = "디버프"
L["SUBCAT_TEXTS"]          = "텍스트"
L["SUBCAT_HEAL_PRED"]      = "치유 예측"
L["SUBCAT_FADER"]          = "페이드"
L["SUBCAT_EFFECTS"]        = "위협/하이라이트"
L["SUBCAT_CUSTOM_TEXT"]    = "커스텀 텍스트"
L["SUBCAT_ALT_POWER"]     = "보조 자원 바"
L["SUBCAT_INDICATORS"]     = "인디케이터"
L["SUBCAT_LAYOUT"]         = "레이아웃"
L["SUBCAT_DISPELS"]        = "해제"

------------------------------------------------------------------------
-- GLOBAL SETTINGS PAGE
------------------------------------------------------------------------
L["GLOBAL_HEADER"]         = "전역 설정"
L["GLOBAL_DESC"]           = "모든 유닛 프레임에 적용되는 전역 설정"
L["HIDE_BLIZZARD"]         = "블리자드 프레임 숨기기"
L["AGGRO_COLOR"]           = "어그로 시 체력바 색상 변경"
L["FADING_SETTINGS"]       = "페이딩 설정"
L["OOR_ALPHA"]             = "범위 밖 투명도"
L["DEAD_ALPHA"]            = "사망 시 투명도"
L["OFFLINE_ALPHA"]         = "오프라인 투명도"
L["CORE_SYSTEM"]           = "코어 시스템"
L["SMOOTH_BARS"]           = "부드러운 바 애니메이션"
L["PIXEL_PERFECT"]         = "픽셀 퍼펙트 모드"
L["DEAD_DESAT"]            = "사망 시 회색 처리"
L["OFFLINE_DESAT"]         = "오프라인 시 회색 처리"
L["NUMBER_FORMAT"]         = "숫자 표시 형식"
L["UNIT_NOTATION"]         = "단위 표기"
L["NOTATION_WESTERN"]      = "서양식 (K, M, B)"
L["NOTATION_KOREAN"]       = "동양식 (만, 억, 조)"
L["DECIMAL_PLACES"]        = "소수점 자릿수"

------------------------------------------------------------------------
-- MEDIA PAGE
------------------------------------------------------------------------
L["MEDIA_HEADER"]          = "미디어 설정"
L["MEDIA_DESC"]            = "폰트와 텍스처 설정"
L["STATUSBAR_TEXTURE"]     = "StatusBar 텍스처"
L["DEFAULT_TEXTURE"]       = "기본 텍스처"
L["DEFAULT_FONT"]          = "기본 폰트"
L["FONT_PREVIEW_TEXT"]     = "가나다 ABC 123"
L["FONT_FACE"]             = "폰트 서체"

------------------------------------------------------------------------
-- COLORS PAGE
------------------------------------------------------------------------
L["COLORS_HEADER"]         = "색상 설정"
L["COLORS_DESC"]           = "전역 색상 및 시각적 설정"
L["UNITFRAME_COLORS"]      = "유닛 프레임 색상"
L["HEALTH_BAR_COLOR"]      = "체력바 색상"
L["HEALTH_LOSS_COLOR"]     = "체력 손실 색상"
L["DEAD_COLOR"]            = "사망 시 색상"
L["OFFLINE_COLOR"]         = "오프라인 시 색상"
L["REACTION_COLORS"]       = "반응 색상"
L["REACTION_FRIENDLY"]     = "우호적"
L["REACTION_HOSTILE"]      = "적대적"
L["REACTION_NEUTRAL"]      = "중립"
L["REACTION_TAPPED"]       = "선점됨"
L["CASTBAR_COLORS"]        = "시전바 색상"
L["INTERRUPTIBLE"]         = "차단 가능"
L["NON_INTERRUPTIBLE"]     = "차단 불가"
L["SHIELD_HEAL_PRED"]      = "보호막 / 치유 예측"
L["SHIELD"]                = "보호막"
L["OVER_SHIELD"]           = "초과 보호막"
L["HEAL_PREDICTION"]       = "치유 예측"
L["HEAL_ABSORB"]           = "치유 흡수"
L["HIGHLIGHT_COLORS"]      = "하이라이트 색상"
L["TARGET_HIGHLIGHT"]      = "대상 하이라이트"
L["MOUSEOVER_HIGHLIGHT"]   = "마우스오버 하이라이트"
L["POWER_BAR_COLORS"]      = "자원 바 색상"

------------------------------------------------------------------------
-- POWER TYPE NAMES
------------------------------------------------------------------------
L["POWER_MANA"]            = "마나"
L["POWER_RAGE"]            = "분노"
L["POWER_ENERGY"]          = "기력"
L["POWER_FOCUS"]           = "집중"
L["POWER_RUNIC_POWER"]     = "룬 마력"
L["POWER_LUNAR_POWER"]     = "천공의 힘"
L["POWER_MAELSTROM"]       = "소용돌이"
L["POWER_INSANITY"]        = "광기"
L["POWER_FURY"]            = "분노(DH)"
L["POWER_PAIN"]            = "고통"

------------------------------------------------------------------------
-- CLASS RESOURCE COLORS
------------------------------------------------------------------------
L["CLASS_RESOURCE_COLORS"] = "직업 자원 색상"
L["COMBO_POINTS_1_7"]     = "콤보 포인트 (1~7)"
L["CHARGED"]               = "충전됨"
L["HOLY_POWER"]            = "신성한 힘"
L["ARCANE_CHARGES"]        = "비전 충전"
L["SOUL_SHARDS"]           = "영혼 조각"
L["RUNES_DK"]              = "룬 (죽음의 기사)"
L["RUNE_BLOOD"]            = "혈기"
L["RUNE_FROST"]            = "냉기"
L["RUNE_UNHOLY"]           = "부정"
L["CHI_MONK"]              = "기 (수도사)"
L["ESSENCE_EVOKER"]        = "정수 (기원사)"
L["ESSENCE_COLOR"]         = "정수 색상"

------------------------------------------------------------------------
-- MODULES PAGE
------------------------------------------------------------------------
L["MODULES_HEADER"]        = "모듈 설정"
L["MODULES_DESC"]          = "추가 기능 모듈 활성화/비활성화"
L["CLICK_CASTING"]         = "클릭 캐스팅"
L["CLICK_CAST_DESC"]       = "유닛프레임 클릭 시 수정키 조합으로 주문 시전 (전투 중 변경 불가)"
L["CLICK_CAST_ENABLE"]     = "클릭 캐스팅 활성화"
L["MOD_NONE"]              = "없음"
L["BTN_LEFT"]              = "좌클릭"
L["BTN_RIGHT"]             = "우클릭"
L["BTN_MIDDLE"]            = "휠클릭"
L["BTN_4"]                 = "버튼4"
L["BTN_5"]                 = "버튼5"
L["BTN_LEFT_SHORT"]        = "좌"
L["BTN_RIGHT_SHORT"]       = "우"
L["BTN_MIDDLE_SHORT"]      = "휠"
L["BTN_N_SHORT"]           = "버튼"
L["NO_BINDING"]            = "(바인딩 없음)"
L["SELECT_SPELL"]          = "주문 선택..."
L["SPELLBOOK"]             = "스펠북"
L["SPELLBOOK_SELECT"]      = "스펠북에서 주문 선택"
L["SPELL_SEARCH"]          = "주문 이름 검색..."
L["OR_ID"]                 = "또는 ID:"
L["ADD_BINDING"]           = "바인딩 추가"
L["REMOVE_LAST"]           = "마지막 삭제"
L["COMBAT_CHANGE_DENIED"]  = "전투 중에는 클릭캐스팅을 변경할 수 없습니다."

------------------------------------------------------------------------
-- TARGET SPELL WARNING MODULE
------------------------------------------------------------------------
L["TARGET_SPELL_WARNING"]  = "수신 주문 경고"
L["TARGET_SPELL_DESC"]     = "적이 아군을 대상으로 주문 시전 시 해당 프레임 강조 표시"
L["TARGET_SPELL_ENABLE"]   = "수신 주문 경고 활성화"
L["WARNING_COLOR"]         = "경고 색상"

------------------------------------------------------------------------
-- MY BUFF INDICATOR MODULE
------------------------------------------------------------------------
L["MY_BUFF_INDICATOR"]     = "내 버프 인디케이터"
L["MY_BUFF_DESC"]          = "내가 시전한 버프가 대상에 적용 시 체력바 하단에 색상 바 표시 (HoT 추적)"
L["MY_BUFF_ENABLE"]        = "내 버프 인디케이터 활성화"
L["MAX_DISPLAY"]           = "최대 표시 수"
L["BAR_HEIGHT"]            = "바 높이"
L["SPACING"]               = "간격"
L["POS_BOTTOM"]            = "하단"
L["POS_TOP"]               = "상단"
L["POSITION"]              = "위치"
L["DEFAULT_COLOR_NIL_CLASS"] = "기본 색상 (nil=클래스색)"
L["RESTORE_CLASS_COLOR"]   = "클래스색 복원"

------------------------------------------------------------------------
-- PRIVATE AURA MODULE
------------------------------------------------------------------------
L["PRIVATE_AURA"]          = "비공개 오라"
L["PRIVATE_AURA_DESC"]     = "블리자드 제어 비공개 오라 표시 (보스 메커닉 디버프 등)"
L["PRIVATE_AURA_ENABLE"]   = "비공개 오라 표시 활성화"
L["PRIVATE_AURA_RELOAD"]   = "비공개 오라 변경은 /reload 후 적용됩니다."
L["ICON_SIZE"]             = "아이콘 크기"
L["MAX_COUNT"]             = "최대 수"
L["PRIVATE_AURA_SIZE_RELOAD"] = "비공개 오라 크기 변경은 /reload 후 적용됩니다."
L["PRIVATE_AURA_COUNT_RELOAD"] = "비공개 오라 개수 변경은 /reload 후 적용됩니다."
L["DIR_RIGHT"]             = "오른쪽"
L["DIR_LEFT"]              = "왼쪽"
L["DIR_UP"]                = "위"
L["DIR_DOWN"]              = "아래"
L["PRIVATE_AURA_DIR_RELOAD"] = "비공개 오라 방향 변경은 /reload 후 적용됩니다."
L["GROWTH_DIRECTION"]      = "성장 방향"

------------------------------------------------------------------------
-- DISPEL HIGHLIGHT MODULE
------------------------------------------------------------------------
L["DISPEL_HIGHLIGHT"]      = "해제 강조"
L["DISPEL_HL_DESC"]        = "해제 가능한 디버프 존재 시 프레임 테두리 색상 강조 (파티/레이드)"
L["DISPEL_HL_ENABLE"]      = "해제 강조 활성화"
L["DISPEL_HL_RELOAD"]      = "해제 강조 변경은 /reload 후 적용됩니다."
L["DISPEL_ONLY"]           = "해제 가능한 것만 표시"
L["HL_MODE_BORDER"]        = "테두리 색상"
L["HL_MODE_GLOW"]          = "글로우 효과"
L["HL_MODE_GRADIENT"]      = "그라데이션"
L["HL_MODE_ICON"]          = "아이콘"
L["HL_MODE"]               = "강조 모드"
L["GLOW_PIXEL"]            = "픽셀"
L["GLOW_SHINE"]            = "빛남"
L["GLOW_PROC"]             = "전문기 효과"
L["GLOW_TYPE"]             = "글로우 타입"
L["GLOW_THICKNESS"]        = "글로우 두께"
L["GRADIENT_ALPHA"]        = "그라데이션 투명도"
L["ICON_POSITION"]         = "아이콘 위치"
L["POS_TOPRIGHT"]          = "우측상단"
L["POS_TOPLEFT"]           = "좌측상단"
L["POS_BOTTOMRIGHT"]       = "우측하단"
L["POS_BOTTOMLEFT"]        = "좌측하단"
L["POS_CENTER"]            = "중앙"

------------------------------------------------------------------------
-- HEALTH GRADIENT MODULE
------------------------------------------------------------------------
L["HEALTH_GRADIENT"]       = "체력 그라데이션"
L["HEALTH_GRADIENT_DESC"]  = "체력 비율에 따라 체력바 색상을 그라데이션으로 표시 (빨강 → 노랑 → 초록)"
L["HEALTH_GRADIENT_ENABLE"] = "체력 그라데이션 활성화"
L["HEALTH_GRADIENT_RELOAD"] = "체력 그라데이션 변경은 /reload 후 적용됩니다."
L["DANGER_0"]              = "위험 (0%)"
L["NORMAL_50"]             = "보통 (50%)"
L["SAFE_100"]              = "안전 (100%)"

------------------------------------------------------------------------
-- PROFILES PAGE
------------------------------------------------------------------------
L["PROFILES_HEADER"]       = "프로필 관리"
L["PROFILES_DESC"]         = "설정 프로필 생성, 전환, 가져오기/내보내기"
L["CURRENT_PROFILE"]       = "현재 프로필"
L["SWITCH"]                = "전환"
L["CREATE_PROFILE"]        = "프로필 생성"
L["NEW_PROFILE_NAME"]      = "새 프로필 이름:"
L["PROFILE_NAME_PLACEHOLDER"] = "프로필 이름 입력..."
L["COPY_SOURCE"]           = "복사 원본:"
L["CREATE_PROFILE_BTN"]    = "프로필 생성"
L["ERROR_PREFIX"]          = "오류: "
L["UNKNOWN_ERROR"]         = "알 수 없는 오류"
L["ENTER_PROFILE_NAME"]    = "프로필 이름을 입력하세요."
L["DELETE_PROFILE"]        = "프로필 삭제"
L["CANNOT_DELETE_DEFAULT"]  = "기본 프로필은 삭제할 수 없습니다."
L["RESET_PROFILE"]         = "프로필 초기화"
L["RESET_CURRENT"]         = "현재 프로필 초기화"
L["IMPORT_EXPORT"]         = "가져오기 / 내보내기"
L["EXPORT"]                = "내보내기"
L["IMPORT"]                = "가져오기"
L["PROFILE_IMPORT_DONE"]   = "프로필 가져오기 완료: "

------------------------------------------------------------------------
-- STATIC POPUP DIALOGS
------------------------------------------------------------------------
L["DELETE"]                = "삭제"
L["CANCEL"]                = "취소"
L["RESET_CONFIRM"]         = "현재 프로필을 기본값으로 초기화하시겠습니까?\n이 작업은 되돌릴 수 없습니다."
L["RESET_CONFIRM_BTN"]     = "초기화"
L["RESET_ALL_CONFIRM"]     = "정말로 모든 설정을 초기화하시겠습니까?\n이 작업은 되돌릴 수 없습니다."
L["CONFIRM"]               = "확인"
L["EXPORT_POPUP_TEXT"]      = "프로필 내보내기\n아래 문자열을 복사하세요:"
L["IMPORT_POPUP_TEXT"]      = "프로필 가져오기\n내보내기 문자열을 붙여넣으세요:"
L["IMPORT_BTN"]            = "가져오기"

------------------------------------------------------------------------
-- UNIT GENERAL PAGE
------------------------------------------------------------------------
L["GENERAL_SETTINGS_FMT"]  = "%s 기본 설정"
L["GENERAL_DESC"]          = "프레임 크기, 위치, 외형 설정"
L["ENABLE"]                = "활성화"
L["SIZE"]                  = "크기"
L["WIDTH"]                 = "너비"
L["HEIGHT"]                = "높이"
L["ANCHOR_SETTINGS"]       = "앵커 설정"
L["ATTACH_TO_PARENT"]      = "부모 프레임에 연결"
L["BORDER"]                = "테두리"
L["SHOW_BORDER"]           = "테두리 표시"
L["THICKNESS"]             = "두께"
L["BORDER_COLOR"]          = "테두리 색상"
L["BACKGROUND"]            = "배경"
L["BACKGROUND_COLOR"]      = "배경 색상"
L["COPY_SETTINGS"]         = "설정 복사"
L["COPY_FROM_OTHER"]       = "다른 유닛에서 복사:"
L["COPY"]                  = "복사"
L["RESET_SECTION"]         = "초기화"
L["RESET_UNIT_DEFAULT"]    = "이 유닛 기본값으로 초기화"

------------------------------------------------------------------------
-- HEALTH BAR PAGE
------------------------------------------------------------------------
L["HEALTH_BAR_FMT"]        = "%s 체력바"
L["HEALTH_BAR_DESC"]       = "체력바 상세 설정"
L["COLOR_SETTINGS"]        = "색상 설정"
L["HEALTH_BAR_COLOR_LBL"]  = "체력바 색상"
L["COLOR_CLASS"]           = "직업 색상"
L["COLOR_REACTION"]        = "진영 색상"
L["COLOR_GRADIENT"]        = "그라디언트"
L["COLOR_CUSTOM"]          = "사용자 정의"
L["CUSTOM_COLOR"]          = "사용자 정의 색상"
L["LOSS_HEALTH_COLOR"]     = "손실 체력 색상"
L["LOSS_COLOR_TYPE_LBL"]   = "손실 체력 색상"
L["LOSS_CUSTOM"]           = "사용자 정의"
L["LOSS_CLASS_DARK"]       = "직업 색상 (어둡게)"
L["LOSS_HEALTH_COLOR_CP"]  = "손실 체력 색상"
L["TEXTURE"]               = "텍스처"
L["HEALTH_BAR_TEXTURE"]    = "체력바 텍스처"
L["HEALTH_BAR_OPTIONS"]    = "체력바 옵션"
L["REVERSE_FILL"]          = "체력바 채움 방향 반전"
L["BG_LOSS_COLOR"]         = "체력 손실 색상"
L["BG_TEXTURE"]            = "배경 텍스처"

------------------------------------------------------------------------
-- POWER BAR PAGE
------------------------------------------------------------------------
L["POWER_BAR_FMT"]         = "%s 자원 바"
L["POWER_BAR_DESC"]        = "자원 바 상세 설정"
L["POWER_BAR_ENABLE"]      = "자원 바 활성화"
L["SAME_WIDTH_AS_HEALTH"]  = "체력바와 같은 너비 사용"
L["USE_POWER_COLOR"]       = "자원 유형별 색상 사용"
L["USE_CLASS_COLOR"]       = "직업 색상 사용"
L["CUSTOM_POWER_COLOR"]    = "사용자 지정 색상"
L["DISPLAY_CONDITIONS"]    = "표시 조건"
L["HIDE_OOC"]              = "전투 중이 아닐 때 숨기기"
L["POWER_BAR_TEXTURE"]     = "자원 바 텍스처"
L["ORIENT_AND_DETACH"]     = "방향 및 분리"
L["BAR_FILL_DIRECTION"]    = "바 채움 방향"
L["DETACH_FROM_FRAME"]     = "프레임에서 분리"

------------------------------------------------------------------------
-- CAST BAR PAGE
------------------------------------------------------------------------
L["CASTBAR_FMT"]           = "%s 시전바"
L["CASTBAR_DESC"]          = "시전바 상세 설정"
L["CASTBAR_ENABLE"]        = "시전바 활성화"
L["CASTBAR_DETACH"]        = "프레임에서 분리"
L["ICON"]                  = "아이콘"
L["SHOW_SPELL_ICON"]       = "주문 아이콘 표시"
L["ICON_POS"]              = "아이콘 위치"
L["ICON_POS_LEFT"]         = "왼쪽"
L["ICON_POS_RIGHT"]        = "오른쪽"
L["TEXT"]                   = "텍스트"
L["SHOW_SPELL_NAME"]       = "주문 이름 표시"
L["SHOW_TIMER"]            = "시간 표시"
L["SPELL_FONT"]            = "주문 폰트"
L["TIMER_FONT"]            = "타이머 폰트"
L["CASTBAR_TEXTURE"]       = "시전바 텍스처"
L["COLOR_OPTIONS"]         = "색상 옵션"
L["CASTBAR_USE_CLASS"]     = "직업 색상 사용"
L["SHOW_INTERRUPT_ONLY"]   = "차단 가능만 표시"
L["INTERRUPTIBLE_COLOR"]   = "차단 가능 색상"
L["NON_INTERRUPT_COLOR"]   = "차단 불가 색상"
L["CASTBAR_BG"]            = "시전바 배경"
L["SPARK_PROGRESS"]        = "스파크 (진행 표시)"
L["SHOW_SPARK"]            = "스파크 표시"
L["SPARK_WIDTH"]           = "스파크 두께"
L["DETACHED_POSITION"]     = "분리 시 위치"

------------------------------------------------------------------------
-- AURA (BUFF/DEBUFF) PAGE
------------------------------------------------------------------------
L["AURA_BUFF"]             = "버프"
L["AURA_DEBUFF"]           = "디버프"
L["SIZE_AND_LAYOUT"]       = "크기 및 배치"
L["ICON_SIZE_AURA"]        = "아이콘 크기"
L["MAX_AURAS"]             = "최대 개수"
L["H_SPACING"]             = "수평 간격"
L["V_SPACING"]             = "수직 간격"
L["PER_LINE"]              = "줄당 개수"
L["DISPLAY_OPTIONS"]       = "표시 옵션"
L["SHOW_DURATION"]         = "지속시간 표시"
L["SHOW_STACKS"]           = "중첩 표시"
L["SHOW_TOOLTIP"]          = "툴팁 표시"
L["FILTER"]                = "필터"
L["DISPEL_ONLY_FILTER"]    = "해제 가능한 것만 표시"
L["BOSS_AURA_PRIORITY"]    = "보스 오라 우선"
L["MY_AURAS"]              = "내가 건 것"
L["OTHER_AURAS"]           = "타인이 건 것"
L["PLAYERS_ONLY"]          = "플레이어가 건 것만"
L["HIDE_NO_DURATION"]      = "지속시간 없는 것 숨기기"
L["MIN_DURATION_SEC"]      = "최소 지속시간(초)"
L["MAX_DURATION_SEC"]      = "최대 지속시간(초)"
L["DIR_AND_POS"]           = "방향 및 위치"
L["INTERACTION"]           = "상호작용"
L["CLICK_THROUGH"]         = "클릭 투과"
L["HIDE_IN_COMBAT"]        = "전투 중 숨기기"
L["WHITELIST_BLACKLIST"]   = "화이트리스트 / 블랙리스트"
L["USE_WHITELIST"]         = "화이트리스트 사용"
L["WL_PRIORITY"]           = "우선 모드 (다른 필터 무시)"
L["WHITELIST_SPELL_ID"]    = "화이트리스트 (주문 ID)"
L["USE_BLACKLIST"]         = "블랙리스트 사용"
L["BLACKLIST_SPELL_ID"]    = "블랙리스트 (주문 ID)"

------------------------------------------------------------------------
-- TEXTS PAGE
------------------------------------------------------------------------
L["TEXTS_FMT"]             = "%s 텍스트"
L["TEXTS_DESC"]            = "텍스트 위젯 설정 (폰트, 위치, 색상, 형식)"
L["NAME_TEXT"]              = "이름 텍스트"
L["SHOW_NAME"]             = "이름 표시"
L["NAME_FORMAT"]           = "이름 형식"
L["NAME_COLOR"]            = "이름 색상"
L["HEALTH_TEXT"]            = "체력 텍스트"
L["SHOW_HEALTH_TEXT"]      = "체력 텍스트 표시"
L["HEALTH_FORMAT"]         = "체력 형식"
L["SEPARATOR"]             = "구분자"
L["HEALTH_TEXT_COLOR"]     = "체력 텍스트 색상"
L["DEAD_STATUS"]           = "사망 상태 표시"
L["POWER_TEXT"]             = "자원 텍스트"
L["SHOW_POWER_TEXT"]       = "자원 텍스트 표시"
L["POWER_FORMAT"]          = "자원 형식"
L["POWER_COLOR"]           = "자원 색상"
L["ANCHOR_TO_POWER"]       = "자원 바에 고정"

------------------------------------------------------------------------
-- LAYOUT PAGE (Group/Raid)
------------------------------------------------------------------------
L["LAYOUT_FMT"]            = "%s 레이아웃"
L["LAYOUT_DESC"]           = "그룹 배치 설정"
L["GROWTH_DIR"]            = "성장 방향"
L["GROWTH_DOWN"]           = "아래로"
L["GROWTH_UP"]             = "위로"
L["GROWTH_RIGHT"]          = "오른쪽"
L["GROWTH_LEFT"]           = "왼쪽"
L["H_SPACING_LAYOUT"]      = "수평 간격"
L["V_SPACING_LAYOUT"]      = "수직 간격"
L["GROUP_SPACING"]         = "그룹 간격"
L["UNITS_PER_COL"]         = "열당 유닛 수"
L["MAX_COLUMNS"]           = "최대 열 수"
L["GROUP_BY"]              = "그룹 기준"
L["GROUP_BY_GROUP"]        = "그룹"
L["GROUP_BY_ROLE"]         = "역할"
L["GROUP_BY_CLASS"]        = "직업"
L["MAX_GROUPS"]            = "최대 그룹 수"
L["SORT_DIR"]              = "정렬 방향"
L["SORT_ASC"]              = "오름차순"
L["SORT_DESC"]             = "내림차순"
L["SORT_METHOD"]           = "정렬 기준"
L["SORT_INDEX"]            = "인덱스"
L["SORT_NAME"]             = "이름"
L["PARTY_SPACING"]         = "간격"
L["SHOW_PLAYER_IN_PARTY"]  = "파티에서 플레이어 표시"
L["SHOW_IN_RAID"]          = "레이드에서도 표시"

------------------------------------------------------------------------
-- HEAL PREDICTION PAGE
------------------------------------------------------------------------
L["HEAL_PRED_FMT"]         = "%s 치유 예측"
L["HEAL_PRED_DESC"]        = "치유 예측, 치유 흡수, 보호막 바 설정"
L["HEAL_PRED_SECTION"]     = "치유 예측 (Incoming Heal)"
L["SHOW_HEAL_PRED"]        = "치유 예측 표시"
L["SHOW_OVERHEAL"]         = "초과 치유 표시"
L["HEAL_PRED_COLOR"]       = "치유 예측 색상"
L["OVERHEAL_COLOR"]        = "초과 치유 색상"
L["PRED_BAR_ALPHA"]        = "예측 바 투명도"
L["OVERHEAL_ALPHA"]        = "초과 치유 투명도"
L["HEAL_ABSORB_SECTION"]   = "치유 흡수 (Anti-Heal)"
L["SHOW_HEAL_ABSORB"]      = "치유 흡수 표시"
L["HEAL_ABSORB_COLOR"]     = "치유 흡수 색상"
L["SHIELD_BAR_SECTION"]    = "보호막 바 (Absorb Shield)"
L["SHOW_SHIELD_BAR"]       = "보호막 바 표시"
L["SHOW_OVER_SHIELD"]      = "초과 보호막 표시"
L["REVERSE_FILL_SHIELD"]   = "채움 반전"
L["SHIELD_COLOR"]          = "보호막 색상"
L["OVER_SHIELD_COLOR"]     = "초과 보호막 색상"

------------------------------------------------------------------------
-- DISPELS PAGE
------------------------------------------------------------------------
L["DISPELS_FMT"]           = "%s 해제"
L["DISPELS_DESC"]          = "해제 가능한 디버프 오버레이 설정"
L["DISPEL_OVERLAY_ENABLE"] = "해제 오버레이 활성화"
L["HL_TYPE"]               = "하이라이트 방식"
L["HL_TYPE_CURRENT"]       = "현재 디버프"
L["HL_TYPE_ENTIRE"]        = "전체 프레임"
L["DISPEL_TYPES"]          = "해제 유형"
L["DTYPE_MAGIC"]           = "마법"
L["DTYPE_CURSE"]           = "저주"
L["DTYPE_DISEASE"]         = "질병"
L["DTYPE_POISON"]          = "독"
L["DTYPE_BLEED"]           = "출혈"
L["DTYPE_ENRAGE"]          = "격노"
L["ICON_STYLE"]            = "아이콘 스타일"
L["ICON_STYLE_NONE"]       = "없음"
L["ICON_STYLE_ICON"]       = "아이콘"

------------------------------------------------------------------------
-- THREAT/HIGHLIGHT PAGE
------------------------------------------------------------------------
L["THREAT_HL_FMT"]         = "%s 위협/하이라이트"
L["THREAT_HL_DESC"]        = "위협 표시 및 하이라이트 설정"
L["THREAT_DISPLAY"]        = "위협 표시"
L["THREAT_ENABLE"]         = "위협 표시 활성화"
L["THREAT_STYLE"]          = "위협 스타일"
L["THREAT_BORDER"]         = "테두리"
L["THREAT_GLOW"]           = "글로우"
L["BORDER_THICKNESS"]      = "테두리 두께"
L["HIGH_THREAT"]           = "높은 위협"
L["MAX_THREAT"]            = "최고 위협"
L["TANKING"]               = "탱킹 중"
L["HIGHLIGHT_SECTION"]     = "하이라이트"
L["HIGHLIGHT_ENABLE"]      = "하이라이트 활성화"
L["MOUSEOVER_HL"]          = "마우스오버 하이라이트"
L["TARGET_HL"]             = "대상 하이라이트"
L["TARGET_COLOR"]          = "대상 색상"
L["MOUSEOVER_COLOR"]       = "마우스오버 색상"

------------------------------------------------------------------------
-- FADER PAGE
------------------------------------------------------------------------
L["FADER_FMT"]             = "%s 페이드"
L["FADER_DESC"]            = "조건에 따라 프레임을 자동으로 투명하게"
L["FADER_ENABLE"]          = "페이드 시스템 활성화"
L["FADE_CONDITIONS"]       = "페이드 조건 (체크 시 불투명 유지)"
L["IN_RANGE"]              = "사거리 내"
L["IN_COMBAT"]             = "전투 중"
L["MOUSEOVER"]             = "마우스오버"
L["IS_TARGET"]             = "대상일 때"
L["UNIT_IS_TARGET"]        = "유닛이 대상일 때"
L["ALPHA_SETTINGS"]        = "투명도 설정"
L["MAX_ALPHA"]             = "최대 투명도"
L["MIN_ALPHA"]             = "최소 투명도"
L["FADE_DURATION"]         = "전환 시간 (초)"

------------------------------------------------------------------------
-- CUSTOM TEXT PAGE
------------------------------------------------------------------------
L["CUSTOM_TEXT_FMT"]       = "%s 커스텀 텍스트"
L["CUSTOM_TEXT_DESC"]      = "최대 3개의 자유 텍스트 위젯 설정"
L["CUSTOM_TEXT_ENABLE"]    = "커스텀 텍스트 시스템 활성화"
L["FMT_NONE_MANUAL"]      = "없음 (직접 입력)"
L["TEXT_SLOT_FMT"]         = "텍스트 슬롯 %d"
L["TEXT_FORMAT"]           = "텍스트 형식"
L["TAG_PLACEHOLDER"]       = "예: [name] - [health:percent]"
L["TAG_HELP"]              = "태그: [name] [health:percent] [health:current] [power:current] [level] [class] [status]"
L["COLOR"]                 = "색상"

------------------------------------------------------------------------
-- ALT POWER BAR PAGE
------------------------------------------------------------------------
L["ALT_POWER_FMT"]         = "%s 보조 자원 바"
L["ALT_POWER_DESC"]        = "보조 자원 바 (대체 파워) 설정"
L["ALT_POWER_ENABLE"]      = "보조 자원 바 활성화"
L["BAR_TEXTURE"]           = "바 텍스처"

------------------------------------------------------------------------
-- INDICATORS PAGE
------------------------------------------------------------------------
L["INDICATORS_FMT"]        = "%s 인디케이터"
L["INDICATORS_DESC"]       = "아이콘 및 인디케이터 설정"
L["INDICATOR_RESURRECT"]   = "부활"
L["INDICATOR_SUMMON"]      = "소환"
L["RESTING_ICON"]          = "휴식 아이콘"
L["SHOW_RESTING"]          = "휴식 아이콘 표시"
L["HIDE_MAX_LEVEL"]        = "최대 레벨일 때 숨기기"

------------------------------------------------------------------------
-- CLASS RESOURCE PAGE
------------------------------------------------------------------------
L["CLASS_RESOURCE_HEADER"] = "플레이어 직업 자원"
L["CLASS_RESOURCE_DESC"]   = "직업별 자원 바 설정"
L["CLASS_BAR_ENABLE"]      = "직업 자원 바 활성화"
L["HIDE_OOC_CLASS"]        = "전투 중이 아닐 때 숨기기"
L["SAME_WIDTH_HEALTH"]     = "체력바와 같은 너비"
L["VERTICAL_FILL"]         = "수직 채움"
L["CLASS_BAR_TEXTURE"]     = "직업 자원 바 텍스처"
L["SHOW_BORDER_CLASS"]     = "테두리 표시"
L["SHOW_BG"]               = "배경 표시"
L["BG_TEXTURE_CLASS"]      = "배경 텍스처"

------------------------------------------------------------------------
-- MOVER (Edit Mode)
------------------------------------------------------------------------
L["MOVER_LCLICK_SELECT"]   = "좌클릭: 선택  |  Shift+클릭: 다중 선택"
L["MOVER_DRAG_MOVE"]       = "드래그: 이동  |  우클릭: 설정"
L["MOVER_WHEEL_Y"]         = "마우스 휠: Y이동  |  Shift+휠: X이동"
L["MOVER_ARROW_NUDGE"]     = "방향키: 넛지  |  Ctrl+방향: 10px"
L["MOVER_GRID_TOGGLE"]     = "좌클릭: 그리드 ON/OFF"
L["MOVER_GRID_PRESET"]     = "우클릭: 프리셋 사이클 (8/16/32/64)"
L["MOVER_GRID_SLIDER"]     = "슬라이더: 4-64px 연속 조절"
L["MOVER_MULTI_SELECT"]    = "%d개 선택"
L["EDIT_MODE"]             = "편집모드"

------------------------------------------------------------------------
-- INIT (Slash commands)
------------------------------------------------------------------------
L["SLASH_COMMANDS"]        = "명령어:"
L["SLASH_OPTIONS"]         = "/duf - 옵션 패널 열기"
L["SLASH_UNLOCK"]          = "/duf unlock|edit - 편집모드 ON (ESC: 취소, Done: 저장)"
L["SLASH_LOCK"]            = "/duf lock - 편집모드 OFF"
L["SLASH_RESET"]           = "/duf reset - 설정 초기화"
L["SLASH_DEBUG"]            = "/duf debug - 디버그 모드 토글"
L["SLASH_DIAG"]            = "/duf diag - 진단 정보 출력"
L["SLASH_PROFILE_LIST"]    = "/duf profile list - 프로필 목록"
L["SLASH_PROFILE_SWITCH"]  = "/duf profile switch <이름> - 프로필 전환"
L["SLASH_PROFILE_NEW"]     = "/duf profile new <이름> - 프로필 생성"
L["DEBUG_LABEL"]           = "디버그:"
L["EDIT_MODE_OFF"]         = "편집모드 OFF"
L["EDIT_MODE_ON"]          = "편집모드 ON - 드래그하여 이동 | ESC: 취소 | Done: 저장"

------------------------------------------------------------------------
-- DIAGNOSTICS
------------------------------------------------------------------------
L["DIAG_HEADER"]           = "=== ddingUI UF 진단 ==="
L["DIAG_MODULES"]          = "모듈 로드: "
L["DIAG_MISSING"]          = "누락: "
L["DIAG_DB_UNITS"]         = "ns.db 유닛: "
L["DIAG_FRAMES"]           = "프레임: "
L["DIAG_FRAMES_FMT"]       = "프레임: %d개"
L["DIAG_NO_FRAME"]         = "프레임 없음! Spawn 실패?"
L["DIAG_HEADERS"]          = "헤더: "
L["DIAG_HEADERS_FMT"]      = "헤더: %d개"
L["DIAG_UPDATE_OK"]        = "Update 함수: 모두 정상"
L["DIAG_SV"]               = "SavedVariables: "
L["DIAG_SV_FMT"]           = "SavedVariables: %d개 프로필"
L["DIAG_SYS_ENABLED"]      = "시스템 enabled: "
L["DIAG_TOTAL_SLOTS"]      = "총 슬롯: "
L["DIAG_OUF_TAGS"]         = "oUF 등록 태그: "
L["DIAG_DDINGUI_TAGS"]     = "ddingui 태그 등록: "
L["DIAG_RESULT"]           = "결과: "
L["DIAG_MAIN_FRAME"]       = "메인 프레임:"
L["DIAG_SIZE_FMT"]         = "크기:"
L["DIAG_CHILDREN"]         = "자식 프레임 수: "
L["DIAG_NO_FRAME_UNIT"]    = "프레임 없음:"
L["DIAG_HEALTH_DBG"]       = "체력 텍스트 디버그:"

------------------------------------------------------------------------
-- PROFILES (Core/Profiles.lua)
------------------------------------------------------------------------
L["PROFILE_SWITCH"]        = "프로필 전환: "
L["PROFILE_CREATE"]        = "프로필 생성: "
L["PROFILE_DELETE"]        = "프로필 삭제: "
L["PROFILE_RENAME"]        = "프로필 이름 변경: "
L["PROFILE_COPY"]          = "프로필 복사: "
L["PROFILE_RESET"]         = "프로필 초기화: "
L["PROFILE_IMPORT_DONE"]   = "프로필 가져오기 완료: "
L["PROFILE_SYSTEM_NA"]     = "프로필 시스템 사용 불가"
L["PROFILE_LIST"]          = "프로필 목록:"
L["PROFILE_CURRENT"]       = "(현재)"
L["PROFILE_COMMANDS"]      = "프로필 명령어:"

------------------------------------------------------------------------
-- CONFIG (defaults)
------------------------------------------------------------------------
L["INTERRUPTED"]           = "중단됨"
L["DEAD"]                  = "사망"

------------------------------------------------------------------------
-- PREVIEW
------------------------------------------------------------------------
L["PREVIEW_LABEL"]         = "미리보기"
L["SPELL_CASTING"]         = "주문 시전"
L["DUMMY_TANK"]            = "탱커"
L["DUMMY_HEALER"]          = "힐러"
L["DUMMY_MAGE"]            = "마법사"
L["DUMMY_ROGUE"]           = "도적"
L["DUMMY_HUNTER"]          = "사냥꾼"
L["DUMMY_PALADIN"]         = "성기사"
L["DUMMY_DRUID"]           = "드루이드"
L["DUMMY_WARLOCK"]         = "흑마"
L["DUMMY_SHAMAN"]          = "주술사"
L["DUMMY_DK"]              = "죽기"
L["DUMMY_MONK"]            = "수도승"
L["DUMMY_DH"]              = "악사"
L["DUMMY_EVOKER"]          = "용술사"
L["DUMMY_WARRIOR"]         = "전사"
L["DUMMY_PRIEST"]          = "사제"
L["DUMMY_ARCANIST"]        = "비전술사"
L["DUMMY_ASSASSIN"]        = "암살자"
L["DUMMY_SNIPER"]          = "저격수"
L["DUMMY_PROTECTOR"]       = "보호기사"
L["DUMMY_RESTO_DRUID"]     = "회복드루"
L["DUMMY_BOSS1"]           = "대왕거미"
L["DUMMY_BOSS2"]           = "보스 부관"
L["DUMMY_BOSS3"]           = "정예 부하"
L["DUMMY_ARENA1"]          = "적 전사"
L["DUMMY_ARENA2"]          = "적 사제"
L["DUMMY_ARENA3"]          = "적 도적"

------------------------------------------------------------------------
-- SEARCH (Options.lua search)
------------------------------------------------------------------------
L["SEARCH_RESULTS_FMT"]    = "검색 결과  |cff999999(%d개 발견)|r"

------------------------------------------------------------------------
-- TAG REFERENCE
------------------------------------------------------------------------
L["TAG_REFERENCE"]         = "태그 레퍼런스"
L["TAG_COPY_HINT"]         = "태그를 클릭하면 여기에 복사됩니다"
L["TAG_CLICK_COPY"]        = "클릭 → 복사 | Ctrl+C로 붙여넣기"
L["TAG_CAT_NAME"]          = "이름"
L["TAG_CAT_HEALTH"]        = "체력"
L["TAG_CAT_POWER"]         = "자원"
L["TAG_CAT_SHIELD"]        = "보호막 / 흡수 / 힐"
L["TAG_CAT_COLOR"]         = "색상 (앞에 붙이고 |r로 종료)"
L["TAG_CAT_STATUS"]        = "상태 / 레벨 / 분류"
L["TAG_CAT_EXAMPLE"]       = "조합 예시"

-- Tag descriptions
L["TAG_FULLNAME"]          = "풀네임"
L["TAG_SHORTNAME"]         = "짧은 이름 (8자)"
L["TAG_MEDNAME"]           = "중간 이름 (14자)"
L["TAG_RAIDNAME"]          = "레이드용 (6자)"
L["TAG_VSHORTNAME"]        = "매우 짧은 (4자)"
L["TAG_ABBREV"]            = "약칭"
L["TAG_ROLE_NAME"]         = "역할아이콘 + 이름"
L["TAG_HEALTH_SMART"]      = "스마트 (풀이면 이름)"
L["TAG_HEALTH_PCT"]        = "퍼센트 (100% 숨김)"
L["TAG_HEALTH_PCT_FULL"]   = "퍼센트 (항상 표시)"
L["TAG_HEALTH_CUR"]        = "현재값"
L["TAG_HEALTH_MAX"]        = "최대값"
L["TAG_HEALTH_CUR_MAX"]    = "현재 / 최대"
L["TAG_HEALTH_CUR_PCT"]    = "현재 | 퍼센트"
L["TAG_HEALTH_DEFICIT"]    = "감소량"
L["TAG_HEALTH_RAID"]       = "레이드 (100% 숨김)"
L["TAG_HEALTH_HEALER"]     = "힐러전용 감소량"
L["TAG_HEALTH_ABSORB"]     = "현재 + 보호막"
L["TAG_POWER_CUR"]         = "자원 현재값"
L["TAG_POWER_PCT"]         = "자원 퍼센트"
L["TAG_POWER_CUR_MAX"]     = "자원 / 최대"
L["TAG_POWER_DEFICIT"]     = "자원 감소량"
L["TAG_POWER_HEALER"]      = "힐러전용 자원"
L["TAG_ABSORB"]            = "보호막 (피해흡수)"
L["TAG_ABSORB_PCT"]        = "보호막 퍼센트"
L["TAG_HEALABSORB"]        = "힐 흡수 (괴사일격 등)"
L["TAG_INCHEAL"]           = "수신 힐량"
L["TAG_CLASSCOLOR"]        = "직업 색상"
L["TAG_HEALTHCOLOR"]       = "체력비율 색상"
L["TAG_POWERCOLOR"]        = "자원타입 색상"
L["TAG_REACTIONCOLOR"]     = "우호/적대 색상"
L["TAG_STATUS"]            = "죽음/오프라인/AFK"
L["TAG_LEVEL"]             = "레벨"
L["TAG_LEVEL_SMART"]       = "스마트레벨 (보스/엘리트)"
L["TAG_OUF_NAME"]          = "이름"
L["TAG_OUF_PERHP"]         = "체력%"
L["TAG_OUF_PERPP"]         = "자원%"
L["TAG_OUF_CURHP"]         = "현재체력 (raw)"
L["TAG_OUF_MAXHP"]         = "최대체력"
L["TAG_OUF_MISSINGHP"]     = "부족체력"
L["TAG_OUF_CURPP"]         = "자원"
L["TAG_OUF_LEVEL"]         = "레벨"
L["TAG_OUF_DEAD"]          = "죽음"
L["TAG_OUF_OFFLINE"]       = "오프라인"
L["TAG_OUF_THREAT"]        = "위협"
L["TAG_OUF_RAIDCOLOR"]     = "직업색"
L["TAG_OUF_POWERCOLOR"]    = "자원색"
L["TAG_EX_CLASS_NAME"]     = "직업색 이름"
L["TAG_EX_HEALTH_PCT"]     = "체력색 퍼센트"
L["TAG_EX_HEALTH_SHIELD"]  = "체력 (보호막)"
