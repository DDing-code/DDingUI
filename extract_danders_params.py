#!/usr/bin/env python3
"""
DandersFrames 파라미터 완전 추출 스크립트
raid/party 섹션의 모든 파라미터와 타입 나열
"""
import re

def get_value_type(line):
    """값 타입 판별"""
    line = line.strip()
    if '= {' in line:
        return 'table'
    elif line.endswith('true,') or line.endswith('false,'):
        return 'boolean'
    elif '"' in line.split('=')[1] if '=' in line else '':
        return 'string'
    elif re.search(r'=\s*-?\d+\.?\d*,?\s*$', line):
        return 'number'
    return 'unknown'

def extract_params(file_path, section_name, start_line, end_line):
    """특정 섹션의 파라미터 추출"""
    with open(file_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    params = {}
    i = start_line

    while i <= end_line:
        line = lines[i]

        # 최상위 키 매칭 (들여쓰기 없이 시작)
        match = re.match(r'^\["([^"]+)"\]\s*=\s*(.+)$', line)
        if match:
            key = match.group(1)
            value_part = match.group(2).strip()

            # 타입 판별
            if value_part == '{':
                # 다음 라인 확인
                if i + 1 <= end_line:
                    next_line = lines[i + 1].strip()
                    # 색상 테이블인지 확인
                    if next_line.startswith('["r"]') or next_line.startswith('["a"]'):
                        params[key] = 'color_table (r, g, b, [a])'
                    # 배열인지 확인 (따옴표로 감싼 값)
                    elif next_line.startswith('"'):
                        params[key] = 'string_array'
                    # 일반 테이블
                    else:
                        params[key] = 'table'
            elif value_part.rstrip(',') in ['true', 'false']:
                params[key] = 'boolean'
            elif value_part.startswith('"'):
                params[key] = 'string'
            elif re.match(r'-?\d+\.?\d*,?$', value_part):
                params[key] = 'number'
            else:
                params[key] = 'unknown'

        i += 1

    return params

# 파일 경로
file_path = r'G:\wow2\World of Warcraft\_retail_\WTF\Account\19178509#5\SavedVariables\DandersFrames.lua'

# 섹션 경계 (수동으로 확인한 값)
# ["My Profile"] at line 167 (index 166)
# ["raid"] at line 168 (index 167)
# ["party"] at line 1214 (index 1213)

print("=" * 100)
print("DANDERS FRAMES - COMPLETE PARAMETER STRUCTURE")
print("=" * 100)
print()

# Raid 섹션 추출
print("RAID SECTION PARAMETERS")
print("-" * 100)
raid_params = extract_params(file_path, 'raid', 167, 1212)
for key in sorted(raid_params.keys()):
    print(f"raid.{key} = {raid_params[key]}")

print(f"\nTotal raid parameters: {len(raid_params)}\n")

# Party 섹션 추출
print("=" * 100)
print("PARTY SECTION PARAMETERS")
print("-" * 100)
party_params = extract_params(file_path, 'party', 1213, 2224)
for key in sorted(party_params.keys()):
    print(f"party.{key} = {party_params[key]}")

print(f"\nTotal party parameters: {len(party_params)}\n")

# 차이 분석
print("=" * 100)
print("DIFFERENCE ANALYSIS")
print("=" * 100)

raid_only = set(raid_params.keys()) - set(party_params.keys())
party_only = set(party_params.keys()) - set(raid_params.keys())

if raid_only:
    print("\nRAID-ONLY parameters:")
    print("-" * 100)
    for key in sorted(raid_only):
        print(f"raid.{key} = {raid_params[key]}")

if party_only:
    print("\nPARTY-ONLY parameters:")
    print("-" * 100)
    for key in sorted(party_only):
        print(f"party.{key} = {party_params[key]}")

# 공통 파라미터
common_params = set(raid_params.keys()) & set(party_params.keys())
print(f"\nCommon parameters: {len(common_params)}")
print(f"Raid-only parameters: {len(raid_only)}")
print(f"Party-only parameters: {len(party_only)}")
