직접 제작한 TGA 스프라이트 시트를 여기에 넣으세요. 게임 안에서 등록할 필요는 없습니다.

## 만해 · 미나즈키 v2 — 움직임과 타격감 (2026-10-08)

사용자 피드백을 반영해 낮은 준비 → 발성에 맞춘 급격한 분출 → 휘감기와 반동 → 빠른 배수로 고쳤습니다. 1.75초에 분출이 시작되고 약0.13초 만에 최대 높이에 도달합니다. 원화35개를 구간마다 다른 길이로 노출한 88프레임/24 FPS/3.667초이며, 원화 확대·회전·모핑·보간은 없습니다. 효과음 클린본은 유지합니다.
현재 파일은 `Minazuki.tga`~`Minazuki_6.tga`, 각2048×2048/4×4/512px 셀/32비트 RGBA 무압축, 마지막8칸 투명,기본 표시배율2입니다. 원화 실제 폭은 최대 약430px입니다. 제작기 `tools/build_minazuki.py`, 새 원화·정확한 프롬프트 `tools/sources/minazuki/v2/`, 검증 시트 `artifacts/DDingUI_FX/minazuki/v2-build/`, 실제 시트로 복원한 `Minazuki-preview-v2.webp` 및 소리 포함 `.mp4`를 제공합니다.
빌더의 원화35개/노출 합계/분출 시각/분출 중 고정 바닥/투명 여백·끝/6페이지 픽셀 복원/WebP 자세·지속시간 검사와 기존 Lua 검사(새6페이지 전환·반복·종료·중간 썸네일 포함)를 통과했습니다. 실제 게임 재생은 미확인입니다. 게임 완전 종료 후 재실행해 텍스처를 갱신하세요.

### 이전 v1

`Minazuki.tga`~`Minazuki_3.tga` / **만해 · 미나즈키** (`minazuki`, 2026-10-08): 우노하나의 원작 만해 장면을 참고해 붉은 웅덩이가 모이고 액체 장막이 솟았다가 흘러내리는 연속 원화를 만들었습니다. 40프레임/11 FPS/약3.64초, 2048×2048 무압축32비트 RGBA 3장, 4×4/512px 셀/기본 배율2. 마지막 시트의 8칸은 투명합니다. 그림의 실제 폭은 최대 약310px이며 확대·회전·보간 없이 원화별 중심/바닥을 정수 좌표로 맞췄습니다.
원작 일본어 “만해… 미나즈키”는 보컬 분리와 구간 편집으로 클린본을 만들었고 `DD_Minazuki` 효과음으로 등록했습니다. 48kHz mono192kbps/3.64초, 측정 -12.62 LUFS/-1.70dBTP. 화면 효과와 소리는 기존 설정에서 각각 선택합니다. 사용자 규칙과 저장 형식은 유지합니다.
재빌드: `python DDingUI_FX/tools/build_minazuki.py`. 원화·정확한 생성 프롬프트·음성 출처와 편집 기록은 `tools/sources/minazuki/`에 있습니다. 제작기는 `artifacts/DDingUI_FX/minazuki/build/`에 검증 후 저장하며, 실제 TGA에서 복원한 WebP/연속 프레임과 소리 포함 MP4 미리보기도 같은 작업 폴더에 있습니다. 40개 고유 프레임·투명 여백·끝·빈 칸·TGA 복원·WebP 픽셀 일치, Lua 목록/페이지 전환/반복/종료 검사를 수행합니다. 실제 게임 화면과 소리 청음은 미확인입니다. 새 미디어는 게임 완전 종료 후 재실행해 확인하세요.

`TimeRewind.tga` / **시간 역행** (`timeRewind`, v2, 2026-09-26): 프레임마다 바늘 길이가 달라지던 문제를 수정했습니다. 내장 image_gen으로 만든 시계판·두 바늘·입자 소재를 분리하고, 바늘은 한 번 정한 크기와 중심으로만 회전합니다. 외곽 입자24개와 빛 꼬리2개는 반시계 방향으로 계속 이동하며, 같은 시계 조각이 모였다가 안쪽으로 회수됩니다. 렌더링한 바늘 길이 편차1.96/1.43px, 최종 TGA의 외곽 이동5도/프레임 검사 통과. 원화 확대·광학 흐름 보간은 없습니다.
60프레임/20 FPS/3초, 4096×4096 무압축32비트 RGBA 한 장,8×8/512px 셀/최소32px 투명 여백,마지막4칸 투명,기본 배율1.5 및 기존 키·효과음 설정 유지. 재빌드: `python DDingUI_FX/tools/build_time_rewind.py`. `artifacts/DDingUI_FX/time-rewind/v2-build/TimeRewind.tga`에서 검증 후 Media로 복사합니다. 원화/정확한 프롬프트는 `sequence-v2/components.png`와 `SPRITE-PROMPTS-v2.md`, 실제 TGA 복원 미리보기는 `TimeRewind-preview-v2.webp`/`.gif`,전체 프레임은 `delivered-frames-v2.png`입니다. 바늘 길이/입자 이동/알파/여백/60개 고유 프레임/TGA 복원/3초 미리보기 및 실제 TOC/Lua5.1 검사를 통과했습니다. 이전v1은 보존했고 실제 WoW 렌더링은 미확인입니다. 게임을 완전히 종료 후 재실행해 확인하세요.

`UnlimitedVoid.tga`부터 `UnlimitedVoid_4.tga` / **무량공처 · 수인** (`unlimitedVoid`, 2026-09-26): 사용자가 채택한 눈·수인 관절 애니메이션 v8입니다. 고정 손등과 관절로 움직이는 검지·중지, 점차 뜨는 눈을 64프레임/20 FPS/3.2초로 재생합니다. 각2048×2048/4×4/512px 셀의 비압축32비트 RGBA TGA 네 장, 기본 표시 배율2입니다. 첫·끝 프레임은 투명하고, 기존 공통 재생부가 네 장을 미리 불러옵니다. 50% 썸네일은 세 번째 시트의 첫 셀입니다.
눈과 손의 세로 간격은 사용자 요청으로 최초 대비 약18px 줄였습니다(512px 표시 기준, 눈만 원본44px 아래 이동; 직전 버전보다 약8px 추가). 손 동작과 재생 시간은 동일합니다.
손 전체는 원본50px(출력약20px) 오른쪽으로 옮겨 수인을 맺은 두 손가락이 양눈의 중앙에 오도록 시각적으로 정렬했습니다.
손목 아래는 약100px 더 짧게 정리하고 끝부분을 부드럽게 투명 처리했습니다(512px 기준). 눈과 수인의 위치·크기·동작은 그대로 유지합니다.
제작 원본과 미리보기는 `artifacts/DDingUI_FX/eyes-hand-mockup/v8/`, 재빌드는 해당 폴더의 `build_rig.py`입니다. `Eyes-Hand-01.tga`~`04.tga`를 위 게임 파일명에 대응해 복사했습니다. 효과음은 설정에서 기존 `DD_Ryoiki_Tenkai` 등을 선택할 수 있습니다. 새 미디어가 보이지 않으면 게임을 완전히 종료 후 재실행하세요. 실제 WoW 화면 재생은 미검증입니다.

사용자 제공 효과음은 Core.lua에서 LibSharedMedia-3.0의 sound로 등록합니다.
- `DD_Hollow Purple` → `DD_Hollow_Purple.mp3`
- `DD_Ryoiki_Tenkai` → `DD_Ryoiki_Tenkai.mp3`
- `DD_Makora` → `DD_Makora.mp3`
- `DD_Zoltraak` → `DD_Zoltraak.mp3` (사용자 제공 프리렌 일본어 음성, +5dB 증폭 및 피크 제한 적용: 평균 음량 약 +4.1dB)
- `DD_Time Rewind` → `DD_Time_Rewind.mp3` (시간 역행용 직접 합성 효과음,3초/48kHz/스테레오/192kbps)

시간 역행 효과음은 시계가 조립되는 역재생 종소리 → 회전 중12번의 역방향 틱·빛 입자 잔향 → 안쪽으로 회수되는 소리로 구성했습니다. 외부 음원/음성 생성 모델은 사용하지 않았습니다. `python DDingUI_FX/tools/build_time_rewind_sound.py`로 WAV 원본과 MP3를 재생성하며, `artifacts/DDingUI_FX/audio/time-rewind/`에 원본·검사 기록·소리 포함 동영상이 있습니다. 파일 길이3초,디코딩 true peak 약-2.81dBFS,평균 RMS 약-21.40dBFS 검사 통과. 게임 효과음 목록에서 직접 선택하며 기존 스킬의 소리 선택은 유지합니다. 실제 WoW 출력은 미확인입니다.

사용자 지정 규칙: 효과음 표시 이름에만 `DD_` 접두사를 붙입니다. TGA 모션 프리셋에는 붙이지 않습니다.
FX가 로드되면 다른 LibSharedMedia 사용 애드온의 효과음 목록에서도 선택할 수 있습니다.

`Presets.lua`의 `FX.Catalog`에 파일별로 아래 형태의 항목을 추가합니다. 실제 파일이 준비된 항목만 넣으세요.

```lua
FX.Catalog = {
    myEffect = {
        name = "내 효과",
        path = "Interface\\AddOns\\DDingUI_FX\\Media\\MyEffect.tga",
        columns = 4,
        rows = 4,
        frames = 16,
        fps = 20,
    },
}
```

`myEffect`는 저장된 스킬과 연결되는 고유 키이므로 배포 후 변경하지 마세요.
블러드 타이머처럼 단일 TGA의 프레임을 왼쪽 → 오른쪽, 위 → 아래 순서로 재생합니다.
열/행은 1~32, 프레임 수는 전체 페이지의 칸 수 이하, FPS는 1~60입니다. 투명 배경은 TGA 알파를 사용합니다.

`HollowPurple.tga` / **허식 · 무라사키**: v9는 청·적이 갑자기 하나로 바뀌던 융합을 보강했습니다.13~24프레임을 새12그림으로 교체해 두 원형 구체가 점점 겹치고 내부 색층이 보라색으로 섞이게 했습니다. 첫12프레임과25~48프레임은 v8과 픽셀 단위로 동일하며, 마지막 **원형 파동 한 줄**을 유지합니다.
4096×4096 무압축32비트 RGBA TGA 한 장,8열×8행,512px 셀/최소32px 투명 여백,48프레임/24 FPS/2초입니다. 마지막16칸은 투명합니다. 기존 키·표시 이름·표시 배율과 재생 시간은 유지합니다.
`tools/build_murasaki.py`는 기존 `sequence-v5/`, 한 줄 파동 `sequence-v8/release-single-wave.png`, 새 융합 `sequence-v9/fusion.png`에서48개 그림을 선택해 패킹합니다. 실제 알파 변환과 실루엣 기준 위치/크기를 정규화하며 원본 확대나 중간 프레임 보간은 없습니다. `v9-build/`에 우선 저장하고 `python DDingUI_FX/tests/test_murasaki_alignment.py artifacts/DDingUI_FX/murasaki/v9-build/HollowPurple.tga` 검사 후 Media로 복사하세요.
정확한 내장 생성 프롬프트/기록은 `artifacts/DDingUI_FX/murasaki/SPRITE-PROMPT-v9.md`, 실제 TGA 복원 미리보기는 `HollowPurple-preview-v9.webp`/`.gif`, 전체 프레임은 `delivered-frames-v9.png`입니다. 융합 최대 폭 변화63→19px, 다른36프레임 보존/원형/중심/크기/단일 파동/알파/여백/TGA 복원/2초 재생 및 실제 TOC/Lua5.1 모의 검사를 통과했습니다. 실제 WoW 렌더링은 미확인입니다.
새 파일을 넣은 뒤에는 게임을 완전히 종료하고 다시 실행하세요.

`HolyWings.tga` / **신성한 날개**: v19 빛 날개 원화에 펼쳐지는 입자 효과를 결합한 v22 스프라이트 시트입니다. 뿌리에 모인 빛에서624개 입자가 흘러나가고, 빛줄기마다 각도가 벌어지며 약1.1초에 걸쳐 날개가 펼쳐집니다. 각 빛줄기의 뿌리와 반지름은 고정합니다.
펼침이 끝나는 시점에 펄럭임도 방향을 바꾸던 타이밍을 조정해, 완성 직후 멈칫하지 않고 같은 방향으로 움직입니다. 끝에는 조금 오므라들면서 빛점으로 풀려 흩어집니다. 생성·소멸 중에도 계속 움직이며 작은 원화 확대와 광학 흐름 보간은 사용하지 않습니다.
결과는 연속120프레임/30 FPS/4초의 TGA 스프라이트 시트입니다. 게임에서는 시트 좌표만 재생합니다.
512×512 셀/32px 여백, `HolyWings.tga`와 `HolyWings_2.tga` 두 장이며 각4096×4096/8열×8행입니다. 기본 표시 배율1.5, NEAREST 필터를 사용합니다.
카탈로그 `pages`는 생략하면1, 2 이상이면 둘째 파일부터 원래 파일명에 `_2`, `_3` 접미사를 붙입니다. 프레임 용량은 열×행×페이지입니다. `displayScale` 기본1이며 실제 표시/편집 크기에 곱합니다.
재생을 시작하기 전에 사용할 페이지를 각각 별도 텍스처로 로드합니다. 재생 중에는 파일을 다시 지정하지 않고 좌표와 표시할 텍스처만 바꿔 시트 전환 시 깜빡임을 방지합니다. 이 재생 코드 수정은 `/reload`로 반영할 수 있습니다.

**앞으로 제작하는 FX와 날개는 무라사키·메이플스토리풍의 세밀한 2D 도트/스프라이트 이펙트를 기준으로 합니다.**
원화·생성 프롬프트·제작 기록: `artifacts/DDingUI_FX/holy-wings/SPRITE-PROMPT-v22.md`와 원화 기록 `SPRITE-PROMPT-v19.md`. TGA에서 복원한 무손실 미리보기 `HolyWings-preview-v22.webp`, 공통 팔레트 GIF `HolyWings-preview-v22.gif`.
재빌드: `python DDingUI_FX/tools/build_holy_wings.py`. `artifacts/DDingUI_FX/holy-wings/v22-build/`에 TGA 두 장과 PNG 사본을 먼저 생성합니다. 미리보기를 확인하고 TGA 두 장을 이 Media 폴더로 복사하세요. 게임을 완전히 종료 후 재실행해 변경된 텍스처를 확인하세요.

`Mahoraga.tga` / **후루베 유라유라 · 마허라** (`mahoraga`): v3는 그림자가 끓는 소환진 → 팔각 법륜 조립 → 막에 감싸인 등장·포효 → 막이 찢어지며 마허라가 드러남 → 입자 소멸의 5초 연출입니다. 바닥 그림자·물결의 형태가 바뀌는 8개 원화 프레임과 감싸임·포효·찢어짐 6개 프레임을 새로 제작했습니다. 법륜에는 살을 따라 흐르는 빛과 빠른 45도 회전을 더했습니다. 기존 머리·상체·팔·옷자락의 관절 동작은 등장 타이밍에 맞춰 이어지며 발은 착지 후 고정됩니다.
120프레임/24 FPS, 512×512 셀/32px 여백, 각4096×4096의 `Mahoraga.tga`와 `Mahoraga_2.tga` 두 장, 기본 표시 배율1.5입니다. 기존 공통 재생부가 두 장을 미리 준비합니다. 효과음은 기존 SharedMedia 선택을 사용합니다.
재빌드: `python DDingUI_FX/tools/build_mahoraga.py`. `artifacts/DDingUI_FX/mahoraga/v3-build/`에서 검증 후 Media로 복사합니다. 내장 image_gen 제작 원화·정확한 프롬프트·참고 자료는 `SPRITE-PROMPT-v3.md`, TGA에서 복원한 미리보기는 `Mahoraga-preview-v3.webp`/`.gif`에 있습니다. 8개 소환진 실루엣·반복 연결, 막이 열릴 때 몸체가 먼저 보이는지, 상대 관절 이동·고정 발·시트 및 Lua 재생 검사를 통과했습니다. 실제 WoW 렌더링은 아직 미확인입니다. 변경된 텍스처는 게임 완전 종료 후 재실행해 확인하세요. 이전 시트는 `v1-build/`와 `v2-build/`에 보존했습니다.

`Zoltraak.tga` / **졸트라크** (`zoltraak`): 사용자 제공 [원작 영상](https://www.youtube.com/shorts/jKApZGyGEyg)의 흰빛·청록색 발광과 원형 문양을 참고한 정면 마법진입니다. v5는 마법진만 표시합니다. 발사 스프라이트·중앙 충전구·충격파·외부 입자를 모두 재생 구성에서 제거했습니다. 승인된 마법진 원화와 역회전은 유지하고, 여섯 원의 순차 점등·선을 따라 반대 방향으로 흐르는 빛·얇은 청록색 후광을 강화했습니다. 중앙과 원형 문양의 빈 공간은 유지합니다.
96프레임/24 FPS/4초, 512×512 셀/32px 투명 여백, 각4096×4096/8×8의 `Zoltraak.tga`와 `Zoltraak_2.tga` 두 장, 기본 표시 배율2/NEAREST입니다. 두 번째 시트의 마지막32칸은 투명합니다. 기존 공통 재생부의 선로딩과 효과음 선택을 사용하며, SharedMedia 효과음 목록에서 `DD_Zoltraak`를 선택할 수 있습니다.
재빌드: `python DDingUI_FX/tools/build_zoltraak.py`. `artifacts/DDingUI_FX/zoltraak/v5-build/`에서 검증 후 Media로 복사합니다. 기존 image_gen 마법진 원화 한 장을 재사용했고 발사 원화는 읽지 않습니다. 제작 기록은 `SPRITE-PROMPT-v5.md`, TGA에서 복원한 미리보기는 `Zoltraak-preview-v5.webp`/`.gif`입니다. 원화 보존/중앙 투명 영역/투명 여백/중간 빈 프레임 없음/페이지 경계/정확한 TGA 복원/4초 재생·반복·종료/50% 썸네일 검사를 통과했습니다. 실제 WoW 렌더링은 미확인입니다. 게임 완전 종료 후 재실행해 텍스처를 갱신하세요. 이전 시트는 각 버전의 빌드 폴더에 보존했습니다.
