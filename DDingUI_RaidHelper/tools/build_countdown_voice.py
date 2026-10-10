#!/usr/bin/env python3
"""Build RaidHelper's Japanese/Korean/English/alarm countdown sounds.

Source: VOICEVOX:猫使ビィ (ノーマル, speaker 58), using the same public synthesis
service as the referenced Japanese voice pack. Korean/English use Microsoft Edge
SunHi/Jenny neural TTS (edge-tts); alarms use ffmpeg sine tones. Speech builds
require network access; all packs require ffmpeg.
48 kHz stereo OGG Vorbis; target -8 LUFS with peak headroom taking priority.
No pitch shift or compression. Retain Media/Sounds/CREDITS.txt when distributing.

    python tools/build_countdown_voice.py
    python tools/build_countdown_voice.py --pack en
"""

import argparse
import asyncio
import json
import math
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen

ADDON_ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = ADDON_ROOT / "Media" / "Sounds"
BASE_URL = "https://voice.acuah.info"
SPEAKER = 58
WORDS = {3: "さん！", 2: "に！", 1: "いち！"}
PACK_WORDS = {
    "ja": WORDS,
    "ko": {3: "셋!", 2: "둘!", 1: "하나!"},
    "en": {3: "Three!", 2: "Two!", 1: "One!"},
    "alarm": {3: "660", 2: "880", 1: "1100"},
}
PACK_PREFIX = {"ja": "Countdown", "ko": "Countdown_KO", "en": "Countdown_EN", "alarm": "Countdown_Alarm"}
PREPARE = (
    "silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.02,"
    "areverse,silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.05,areverse,"
    "afade=t=in:d=0.005,apad=pad_dur=0.12,apad=whole_dur=0.50,aresample=48000"
)
TARGET_LUFS = -8.0
PEAK_CEILING = -2.0


def synthesize(text: str, target: Path, pack: str = "ja") -> None:
    if pack == "alarm":
        ffmpeg("-f", "lavfi", "-i", f"sine=frequency={text}:duration=0.22:sample_rate=48000",
               "-af", "tremolo=f=14:d=0.35,afade=t=out:st=0.16:d=0.06", str(target))
        return
    if pack in ("ko", "en"):
        import edge_tts

        async def save():
            voice = "ko-KR-SunHiNeural" if pack == "ko" else "en-US-JennyNeural"
            await edge_tts.Communicate(text, voice, rate="+15%").save(str(target))

        if sys.platform == "win32":
            asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())
        asyncio.run(save())
        return
    params = urlencode({"text": text, "speaker": SPEAKER})
    with urlopen(Request(f"{BASE_URL}/audio_query?{params}", method="POST"), timeout=60) as response:
        query = json.load(response)
    query.update(speedScale=1.2, volumeScale=0.5, prePhonemeLength=0.02,
                 postPhonemeLength=0.06, outputSamplingRate=48000, outputStereo=True)
    request = Request(f"{BASE_URL}/synthesis?speaker={SPEAKER}",
                      data=json.dumps(query).encode("utf-8"),
                      headers={"Content-Type": "application/json"})
    with urlopen(request, timeout=60) as response:
        target.write_bytes(response.read())


def ffmpeg(*args: str) -> str:
    result = subprocess.run(["ffmpeg", "-y", "-hide_banner", "-nostats", *args],
                            check=True, capture_output=True, text=True, encoding="utf-8", errors="replace")
    return result.stderr


def audio_levels(path: Path) -> tuple[float, float]:
    log = ffmpeg("-i", str(path), "-af", "ebur128=peak=true", "-f", "null", "-")
    loudness = float(re.findall(r"I:\s+(-?[0-9.]+) LUFS", log)[-1])
    peak = float(re.findall(r"Peak:\s+(-?[0-9.]+) dBFS", log)[-1])
    assert math.isfinite(loudness) and math.isfinite(peak) and loudness > -60, "Empty countdown audio"
    return loudness, peak


def main(pack: str = "ja") -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=OUTPUT_DIR) as scratch:
        for number, text in PACK_WORDS[pack].items():
            raw = Path(scratch) / f"raw_{number}{'.mp3' if pack in ('ko', 'en') else '.wav'}"
            prepared = Path(scratch) / f"prepared_{number}.wav"
            synthesize(text, raw, pack)
            ffmpeg("-i", str(raw), "-af", PREPARE, "-ac", "2", str(prepared))
            loudness, peak = audio_levels(prepared)
            target_lufs = -12.0 if pack == "alarm" else TARGET_LUFS
            gain = min(target_lufs - loudness, PEAK_CEILING - peak)
            output = Path(scratch) / f"{PACK_PREFIX[pack]}_{number}.ogg"
            ffmpeg("-i", str(prepared), "-af", f"volume={gain:.2f}dB",
                   "-c:a", "libvorbis", "-q:a", "6", str(output))
            loudness, peak = audio_levels(output)
            assert peak <= -1.0, f"Countdown {number} has insufficient peak headroom"
            info = json.loads(subprocess.check_output(
                ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "json", str(output)]))
            assert 0.4 <= float(info["format"]["duration"]) < 0.9, "Countdown must finish before the next number"
            print(f"Prepared {output.name} ({loudness:.1f} LUFS, {peak:.1f} dBTP)")
        # Keep the installed set intact if any synthesis or validation fails.
        for number in PACK_WORDS[pack]:
            output = Path(scratch) / f"{PACK_PREFIX[pack]}_{number}.ogg"
            output.replace(OUTPUT_DIR / output.name)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pack", choices=tuple(PACK_WORDS), default="ja")
    main(parser.parse_args().pack)
