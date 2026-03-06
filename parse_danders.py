#!/usr/bin/env python3
"""
DandersFrames SavedVariables 파서
raid/party 섹션의 전체 파라미터 구조를 분석
"""
import re
import sys

def parse_lua_value(line):
    """Lua 값의 타입 추론"""
    line = line.strip()
    if line.endswith('{'):
        return 'table'
    elif line.endswith('true') or line.endswith('false'):
        return 'boolean'
    elif line.endswith('"') or line.endswith("'"):
        return 'string'
    elif re.search(r'=\s*\d+\.?\d*\s*,?\s*$', line):
        return 'number'
    return 'unknown'

def extract_structure(lines, start_line, section_name):
    """특정 섹션의 구조 추출"""
    result = {}
    current_path = []
    indent_stack = [0]

    in_section = False
    base_indent = 0

    for i, line in enumerate(lines[start_line:], start=start_line):
        stripped = line.strip()

        # 섹션 시작 감지
        if f'["{section_name}"]' in line and stripped.endswith('{'):
            in_section = True
            base_indent = len(line) - len(line.lstrip())
            continue

        if not in_section:
            continue

        # 섹션 종료 감지 (base_indent와 같은 레벨에서 },)
        current_indent = len(line) - len(line.lstrip())
        if stripped == '},' and current_indent == base_indent:
            break

        # 키-값 파싱
        match = re.match(r'\["([^"]+)"\]\s*=\s*(.+)', stripped)
        if match:
            key = match.group(1)
            value_part = match.group(2)
            value_type = parse_lua_value(value_part)

            # 들여쓰기 레벨로 중첩 구조 파악
            while indent_stack and current_indent <= indent_stack[-1]:
                indent_stack.pop()
                if current_path:
                    current_path.pop()

            full_key = '.'.join(current_path + [key]) if current_path else key
            result[full_key] = value_type

            if value_type == 'table':
                current_path.append(key)
                indent_stack.append(current_indent)

        # 테이블 종료
        elif stripped == '},':
            if indent_stack and len(indent_stack) > 1:
                indent_stack.pop()
                if current_path:
                    current_path.pop()

    return result

# 파일 읽기
file_path = r'G:\wow2\World of Warcraft\_retail_\WTF\Account\19178509#5\SavedVariables\DandersFrames.lua'
with open(file_path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

# profiles 섹션 찾기
profiles_start = 0
for i, line in enumerate(lines):
    if '["profiles"] = {' in line and i < 200:  # DandersFramesDB_v2의 profiles
        profiles_start = i
        break

# My Profile 찾기
my_profile_start = 0
for i, line in enumerate(lines[profiles_start:], start=profiles_start):
    if '["My Profile"]' in line:
        my_profile_start = i
        break

print(f"=== DandersFrames SavedVariables Structure Analysis ===\n")
print(f"Found 'My Profile' at line {my_profile_start + 1}\n")

# raid 섹션 파싱
print("=" * 80)
print("RAID SECTION")
print("=" * 80)
raid_structure = extract_structure(lines, my_profile_start, 'raid')
for key in sorted(raid_structure.keys()):
    print(f"{key} = {raid_structure[key]}")

print(f"\nTotal raid parameters: {len(raid_structure)}\n")

# party 섹션 파싱
print("=" * 80)
print("PARTY SECTION")
print("=" * 80)
party_structure = extract_structure(lines, my_profile_start, 'party')
for key in sorted(party_structure.keys()):
    print(f"{key} = {party_structure[key]}")

print(f"\nTotal party parameters: {len(party_structure)}\n")

# 차이점 분석
raid_only = set(raid_structure.keys()) - set(party_structure.keys())
party_only = set(party_structure.keys()) - set(raid_structure.keys())

if raid_only:
    print("=" * 80)
    print("RAID-ONLY parameters:")
    print("=" * 80)
    for key in sorted(raid_only):
        print(f"{key} = {raid_structure[key]}")

if party_only:
    print("\n" + "=" * 80)
    print("PARTY-ONLY parameters:")
    print("=" * 80)
    for key in sorted(party_only):
        print(f"{key} = {party_structure[key]}")
