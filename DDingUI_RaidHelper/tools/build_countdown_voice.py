#!/usr/bin/env python3
"""Build RaidHelper's Korean countdown voice (셋 · 둘 · 하나) for the upcoming-cooldown alert.

Source: Microsoft Edge neural TTS voice ko-KR-SunHiNeural (needs `pip install edge-tts`
and network access once). Output follows the DDingUI voice loudness standard used by
Profile: 48 kHz stereo OGG Vorbis, about -8 LUFS, true peak below 0 dBTP.

    python tools/build_countdown_voice.py
"""

import asyncio
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ADDON_ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = ADDON_ROOT / "Media" / "Sounds"
VOICE = "ko-KR-SunHiNeural"
WORDS = {3: "셋!", 2: "둘!", 1: "하나!"}
PREPARE = (
    "silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.02,"
    "areverse,silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.05,areverse,"
    "afade=t=in:d=0.01,apad=pad_dur=0.12,aresample=48000"
)
TARGET_LUFS = -8.0
# Short single words cannot reach -8 LUFS through loudnorm alone, so gain is measured per
# word and a brick-wall limiter keeps the true peak under 0 dBTP.
LIMITER = "alimiter=limit=0.94:attack=1:release=40:level=disabled"


async def synthesize(text: str, target: Path) -> None:
    import edge_tts  # imported lazily so the module can be inspected without the package

    await edge_tts.Communicate(text, VOICE, rate="+15%").save(str(target))


def ffmpeg(*args: str) -> str:
    result = subprocess.run(["ffmpeg", "-y", "-hide_banner", "-nostats", *args],
                            check=True, capture_output=True, text=True, encoding="utf-8", errors="replace")
    return result.stderr


def integrated_lufs(path: Path) -> float:
    log = ffmpeg("-i", str(path), "-af", "ebur128", "-f", "null", "-")
    return float(re.findall(r"I:\s+(-?[0-9.]+) LUFS", log)[-1])


def main() -> None:
    if sys.platform == "win32":
        asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as scratch:
        for number, text in WORDS.items():
            raw = Path(scratch) / f"raw_{number}.mp3"
            prepared = Path(scratch) / f"prepared_{number}.wav"
            asyncio.run(synthesize(text, raw))
            ffmpeg("-i", str(raw), "-af", PREPARE, "-ac", "2", str(prepared))
            gain = TARGET_LUFS - integrated_lufs(prepared)
            output = OUTPUT_DIR / f"Countdown_{number}.ogg"
            for _ in range(3):  # the limiter eats some loudness; nudge until within 0.5 LU
                ffmpeg("-i", str(prepared), "-af", f"volume={gain:.2f}dB,{LIMITER}",
                       "-c:a", "libvorbis", "-q:a", "6", str(output))
                loudness = integrated_lufs(output)
                if abs(loudness - TARGET_LUFS) <= 0.5:
                    break
                gain += TARGET_LUFS - loudness
            print(f"Wrote {output} ({loudness:.1f} LUFS)")


if __name__ == "__main__":
    main()
