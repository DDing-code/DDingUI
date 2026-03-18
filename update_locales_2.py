import os

en = r'C:\Users\D2JK\바탕화면\cd\DDingUI_Super\DDingUI\Locales\enUS.lua'
ko = r'C:\Users\D2JK\바탕화면\cd\DDingUI_Super\DDingUI\Locales\koKR.lua'

new_locales = {
    'Tracker Groups': ('Tracker Groups', '추적 트리거 그룹'),
    'Add New Group': ('Add New Group', '새 그룹 추가'),
    'Sort Method': ('Sort Method', '정렬 기준'),
    'Sort Direction': ('Sort Direction', '정렬 방향'),
    'Group Anchor Point': ('Group Anchor Point', '그룹 기준 위치'),
    'Overview': ('Overview', '개요 (Overview)'),
    'No buffs being tracked. Select a buff from the catalog.': ('No buffs being tracked. Select a buff from the catalog.', '추적 중인 버프가 없습니다. 카탈로그에서 추적할 내용을 선택하세요.'),
}

def inject(path, is_kor):
    if not os.path.exists(path):
        return
    with open(path, 'r', encoding='utf-8') as f:
        c = f.read()

    insert_text = '\n-- Buff Tracker Refactor (Phase 1 TreeGroup)\n'
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
