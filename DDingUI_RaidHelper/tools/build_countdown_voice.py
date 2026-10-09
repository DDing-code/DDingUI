#!/usr/bin/env python3
"""Build RaidHelper's Japanese countdown voice (さん · に · いち).

Source: VOICEVOX:猫使ビィ (ノーマル, speaker 58), using the same public synthesis
service as the referenced Japanese voice pack. Requires network access and ffmpeg.
48 kHz stereo OGG Vorbis; target -8 LUFS with peak headroom taking priority.
No pitch shift or compression. Retain Media/Sounds/CREDITS.txt when distributing.

    python tools/build_countdown_voice.py
"""

import json
import math
import re
import subprocess
import tempfile
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen

ADDON_ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = ADDON_ROOT / "Media" / "Sounds"
BASE_URL = "https://voice.acuah.info"
SPEAKER = 58
WORDS = {3: "さん！", 2: "に！", 1: "いち！"}
PREPARE = (
    "silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.02,"
    "areverse,silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.05,areverse,"
    "afade=t=in:d=0.005,apad=pad_dur=0.12,apad=whole_dur=0.50,aresample=48000"
)
TARGET_LUFS = -8.0
PEAK_CEILING = -2.0


def synthesize(text: str, target: Path) -> None:
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


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=OUTPUT_DIR) as scratch:
        for number, text in WORDS.items():
            raw = Path(scratch) / f"raw_{number}.wav"
            prepared = Path(scratch) / f"prepared_{number}.wav"
            synthesize(text, raw)
            ffmpeg("-i", str(raw), "-af", PREPARE, "-ac", "2", str(prepared))
            loudness, peak = audio_levels(prepared)
            gain = min(TARGET_LUFS - loudness, PEAK_CEILING - peak)
            output = Path(scratch) / f"Countdown_{number}.ogg"
            ffmpeg("-i", str(prepared), "-af", f"volume={gain:.2f}dB",
                   "-c:a", "libvorbis", "-q:a", "6", str(output))
            loudness, peak = audio_levels(output)
            assert peak <= -1.0, f"Countdown {number} has insufficient peak headroom"
            info = json.loads(subprocess.check_output(
                ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "json", str(output)]))
            assert 0.4 <= float(info["format"]["duration"]) < 0.9, "Countdown must finish before the next number"
            print(f"Prepared Countdown_{number}.ogg ({loudness:.1f} LUFS, {peak:.1f} dBTP)")
        # Keep the installed set intact if any synthesis or validation fails.
        for number in WORDS:
            output = Path(scratch) / f"Countdown_{number}.ogg"
            output.replace(OUTPUT_DIR / output.name)


if __name__ == "__main__":
    main()
