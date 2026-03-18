import os

en = r'C:\Users\D2JK\바탕화면\cd\DDingUI_Super\DDingUI\Locales\enUS.lua'
ko = r'C:\Users\D2JK\바탕화면\cd\DDingUI_Super\DDingUI\Locales\koKR.lua'

new_locales = {
    'Condition': ('Condition', '조건'),
    'Add Condition': ('Add Condition', '조건(If) 추가'),
    'Remove Condition': ('Remove Condition', '조건 삭제'),
    'Trigger Logic': ('Trigger Logic', '트리거 논리'),
    'Add Check': ('Add Check', '검사 추가'),
    'Add Action': ('Add Action', '동작 추가'),
    'Time Left': ('Time Left', '남은 시간'),
    'Stacks': ('Stacks', '중첩 수'),
    'Active': ('Active', '활성 상태'),
    'Color Override': ('Color Override', '색상 덮어쓰기'),
    'Play Sound': ('Play Sound', '사운드 재생'),
    'Show Glow': ('Show Glow', '반짝임 (Glow) 표시'),
    'Move Up': ('Move Up', '위로 이동'),
    'Move Down': ('Move Down', '아래로 이동'),
    'My Trackers': ('My Trackers', '내 추적기'),
    'CDM Catalog': ('CDM Catalog', '스킬 카탈로그 (CDM)'),
    'Global Settings': ('Global Settings', '글로벌/기본 설정'),
    'Trigger': ('Trigger', '트리거(Trigger)'),
    'Display': ('Display', '디스플레이(Display)'),
    'Conditions': ('Conditions', '조건 및 동작'),
}

def inject(path, is_kor):
    if not os.path.exists(path):
        return
    with open(path, 'r', encoding='utf-8') as f:
        c = f.read()

    insert_text = '\n-- Buff Tracker Refactor (Phase 2 Condition)\n'
    for k, v in new_locales.items():
        val = v[1] if is_kor else v[0]
        val = val.replace('\"', r'\\\"')
        if f'L["{k}"]' not in c:
            insert_text += f'L["{k}"] = "{val}"\n'
            
    with open(path, 'a', encoding='utf-8') as f:
        f.write(insert_text)
    print(f'Injected to {path}')

inject(en, False)
inject(ko, True)
