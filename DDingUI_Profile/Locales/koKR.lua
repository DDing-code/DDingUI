local L = LibStub("AceLocale-3.0"):NewLocale("DDingUI_Profile", "koKR")
if not L then return end

------------------------------------------------------------------------
-- CLASS NAMES
------------------------------------------------------------------------
L["CLASS_WARRIOR"]      = "전사"
L["CLASS_PALADIN"]      = "성기사"
L["CLASS_HUNTER"]       = "사냥꾼"
L["CLASS_ROGUE"]        = "도적"
L["CLASS_PRIEST"]       = "사제"
L["CLASS_DEATHKNIGHT"]  = "죽음의기사"
L["CLASS_SHAMAN"]       = "주술사"
L["CLASS_MAGE"]         = "마법사"
L["CLASS_WARLOCK"]      = "흑마법사"
L["CLASS_MONK"]         = "수도사"
L["CLASS_DRUID"]        = "드루이드"
L["CLASS_DEMONHUNTER"]  = "악마사냥꾼"
L["CLASS_EVOKER"]       = "기원사"

------------------------------------------------------------------------
-- SPECIALIZATION NAMES
------------------------------------------------------------------------
-- Warrior
L["SPEC_ARMS"]          = "무기"
L["SPEC_FURY"]          = "분노"
L["SPEC_PROTECTION_WARRIOR"] = "방어"
-- Paladin
L["SPEC_HOLY_PALADIN"]  = "신성"
L["SPEC_PROTECTION_PALADIN"] = "보호"
L["SPEC_RETRIBUTION"]   = "징벌"
-- Hunter
L["SPEC_BEASTMASTERY"]  = "야수"
L["SPEC_MARKSMANSHIP"]  = "사격"
L["SPEC_SURVIVAL"]      = "생존"
-- Rogue
L["SPEC_ASSASSINATION"] = "암살"
L["SPEC_OUTLAW"]        = "무법"
L["SPEC_SUBTLETY"]      = "잠행"
-- Priest
L["SPEC_DISCIPLINE"]    = "수양"
L["SPEC_HOLY_PRIEST"]   = "신성"
L["SPEC_SHADOW"]        = "암흑"
-- Death Knight
L["SPEC_BLOOD"]         = "혈기"
L["SPEC_FROST_DK"]      = "냉기"
L["SPEC_UNHOLY"]        = "부정"
-- Shaman
L["SPEC_ELEMENTAL"]     = "정기"
L["SPEC_ENHANCEMENT"]   = "고양"
L["SPEC_RESTORATION_SHAMAN"] = "복원"
-- Mage
L["SPEC_ARCANE"]        = "비전"
L["SPEC_FIRE"]          = "화염"
L["SPEC_FROST_MAGE"]    = "냉기"
-- Warlock
L["SPEC_AFFLICTION"]    = "고통"
L["SPEC_DEMONOLOGY"]    = "악마"
L["SPEC_DESTRUCTION"]   = "파괴"
-- Monk
L["SPEC_BREWMASTER"]    = "양조"
L["SPEC_MISTWEAVER"]    = "운무"
L["SPEC_WINDWALKER"]    = "풍운"
-- Druid
L["SPEC_BALANCE"]       = "조화"
L["SPEC_FERAL"]         = "야성"
L["SPEC_GUARDIAN"]      = "수호"
L["SPEC_RESTORATION_DRUID"] = "복원"
-- Demon Hunter
L["SPEC_HAVOC"]         = "파멸"
L["SPEC_VENGEANCE"]     = "복수"
-- Evoker
L["SPEC_DEVASTATION"]   = "황폐"
L["SPEC_PRESERVATION"]  = "보존"
L["SPEC_AUGMENTATION"]  = "증강"

------------------------------------------------------------------------
-- SLASH COMMANDS & CHAT MESSAGES
------------------------------------------------------------------------
L["PROFILE_RESET_MSG"]  = "프로필 설치 상태가 초기화되었습니다. /reload 후 다시 설치할 수 있습니다."
L["USAGE_MSG"]          = "사용법: /ddp [install|load|reset]"
L["COMBAT_LOCKDOWN_MSG"] = "전투 중에는 프로필을 로드할 수 없습니다."
L["UNKNOWN_SPEC"]       = "알 수 없음"

------------------------------------------------------------------------
-- INSTALLER UI - NAVIGATION
------------------------------------------------------------------------
L["NAV_PREV"]           = "◀ 이전"
L["NAV_NEXT"]           = "다음 ▶"
L["NAV_CLOSE"]          = "닫기"

------------------------------------------------------------------------
-- INSTALLER - STEP TITLES
------------------------------------------------------------------------
L["STEP_WELCOME"]       = "환영"
L["STEP_EDITMODE"]      = "편집 모드"
L["STEP_CDM"]           = "쿨다운 매니저"
L["STEP_COMPLETE"]      = "설치 완료"

------------------------------------------------------------------------
-- INSTALLER - PAGE CONTENT
------------------------------------------------------------------------
-- Welcome page (page 1)
L["WELCOME_SUBTITLE"]   = "%s 프로필 설치"
L["WELCOME_DESC1_FRESH"] = "DDingUI 프로필 설치를 시작합니다."
L["WELCOME_DESC2_FRESH"] = "'다음'을 클릭하여 각 애드온별 프로필을 설치하세요."
L["WELCOME_DESC1_EXISTING"] = "이전에 설치된 프로필을 이 캐릭터에 불러옵니다."
L["WELCOME_DESC2_EXISTING"] = "'프로필 불러오기'를 클릭하거나, '다음'으로 다시 설치하세요."
L["LOAD_PROFILES"]      = "프로필 불러오기"

-- Generic addon page
L["ADDON_DISABLED"]     = "%s 애드온이 비활성화 상태입니다."
L["SKIP_STEP"]          = "이 단계를 건너뛰려면 'Continue'를 클릭하세요."
L["APPLY_PROFILE"]      = "%s 프로필을 적용합니다."
L["APPLY"]              = "적용"

-- ElvUI page (page 2)
L["ELVUI_NOT_INSTALLED"] = "ElvUI가 설치되지 않았습니다."
L["ELVUI_SKIP"]         = "ElvUI 프로필 적용을 건너뜁니다. 'Continue'를 클릭하세요."

-- DandersFrames page (page 7)
L["DF_SELECT_ROLE"]     = "역할에 맞는 레이아웃을 선택하세요."
L["DF_DPS_TANK"]        = "DPS / 탱커"
L["DF_HEALER"]          = "힐러"

-- Blizzard Edit Mode page (page 10)
L["EDITMODE_SUBTITLE"]  = "블리자드 편집 모드"
L["EDITMODE_DESC"]      = "기본 편집 모드 레이아웃을 적용합니다."

-- Cooldown Manager page (page 11)
L["CDM_SUBTITLE"]       = "고급 재사용 대기시간"
L["CDM_DESC"]           = "전문화별 고급 재사용 대기시간 레이아웃을 적용합니다."

-- Complete page (page 12)
L["COMPLETE_SUBTITLE"]  = "설치 완료!"
L["COMPLETE_DESC1"]     = "DDingUI 프로필 설치가 완료되었습니다."
L["COMPLETE_DESC2"]     = "'리로드'를 클릭하여 설정을 저장하고 UI를 다시 불러오세요."
L["RELOAD"]             = "리로드"

------------------------------------------------------------------------
-- SETUP MESSAGES
------------------------------------------------------------------------
L["SETUP_COMPLETE"]     = "|cff00ff00%s|r 프로필 적용 완료!"
L["SETUP_NOT_FOUND"]    = "'%s' Setup 함수를 찾을 수 없습니다."

-- Blizzard EditMode Setup
L["EDITMODE_NO_DATA"]   = "편집 모드 레이아웃 데이터가 없습니다."
L["EDITMODE_COPY_TITLE"] = "|cffffffffDDing|r|cffffa300UI|r - 편집 모드 레이아웃"
L["EDITMODE_COPY_DESC"] = "|cff00ff00Ctrl+A|r → |cff00ff00Ctrl+C|r 로 복사 후\n|cffffd200Esc > 편집 모드 > 레이아웃 > 가져오기|r 에서 붙여넣기"

-- CooldownManager Setup
L["CDM_NO_SPEC"]        = "전문화 정보를 가져올 수 없습니다."
L["CDM_NO_DATA"]        = "현재 전문화(specID: %s)의 고급 재사용 대기시간 데이터가 없습니다."
L["CDM_COPY_TITLE"]     = "|cffffffffDDing|r|cffffa300UI|r - 고급 재사용 대기시간"
L["CDM_COPY_DESC"]      = "|cff00ff00Ctrl+A|r → |cff00ff00Ctrl+C|r 로 복사 후  |cffffd200고급 재사용 대기시간 설정 > 가져오기|r 에서 붙여넣기"

-- DandersFrames Setup
L["DF_NO_DATA"]         = "DandersFrames %s 프로필 데이터가 없습니다."
L["DF_INVALID_DATA"]    = "DandersFrames 프로필 데이터가 유효하지 않습니다."
L["DF_DPS_TANK_LABEL"]  = "DPS / 탱커"
L["DF_HEALER_LABEL"]    = "힐러"

------------------------------------------------------------------------
-- COPY FRAME
------------------------------------------------------------------------
L["CONFIRM"]            = "확인"
