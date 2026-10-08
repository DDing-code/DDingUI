# 우노하나 만해 음성 클린본

- 원본: https://www.youtube.com/watch?v=IRORPM2fctk — MAS Content, Unohana BANKAI MINAZUKI in 4K anime | Bleach TYBW Episode 10.
- 원본 일본어 음성을 분리했다. 새 음성 생성·목소리 복제·음높이/속도 변환은 하지 않았다.
- 원본 앞 12초를 44.1kHz stereo float WAV로 변환하고 torchaudio 2.6 `HDEMUCS_HIGH_MUSDB_PLUS`로 vocal stem을 분리했다. 정규화 후 추론하고 원래 진폭으로 되돌렸다.
- 원본 시간 2.10–3.52초(만해), 8.48–10.35초(미나즈키)를 사용하고 사이에 0.35초 무음을 넣었다. 전체 3.64초.
- 각 구간에 10ms 진입, 첫 구간 70ms/둘째 100ms 종료 페이드. 65Hz highpass, 14kHz lowpass. 2pass loudnorm -12 LUFS / -1.5dBTP / LRA7.
- 결과: 48kHz mono 24bit WAV, 48kHz mono 192kbps MP3. 애드온은 `Media/DD_Minazuki.mp3`를 SharedMedia `DD_Minazuki`로 제공한다.
- MP3 측정: -12.62 LUFS, -1.70dBTP, LRA0.20. 비발화 구간의 원본 대비 분리 stem RMS 감소 약 32~39dB. 이를 완전 무잡음이나 대사 청음 검증으로 해석하지 않는다.
- 원본과 중간 파일, 분리 스크립트, WAV 클린본: 저장소의 `artifacts/DDingUI_FX/audio/unohana-minazuki/`(로컬 제작 자료). 원본 영상 전체와 중간 파일은 애드온에 넣지 않는다.
- 사람의 청음 및 실제 게임 소리 재생은 미확인. 분리 과정의 미세 잔향이 남을 수 있다.
