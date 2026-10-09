import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import subprocess


ADDON_ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("countdown_voice", ADDON_ROOT / "tools/build_countdown_voice.py")
voice = importlib.util.module_from_spec(spec)
spec.loader.exec_module(voice)


class CountdownVoiceTests(unittest.TestCase):
    def test_shipped_numbers_fit_the_one_second_countdown(self):
        for number in (3, 2, 1):
            path = ADDON_ROOT / f"Media/Sounds/Countdown_{number}.ogg"
            info = json.loads(subprocess.check_output([
                "ffprobe", "-v", "error", "-show_entries",
                "format=duration:stream=codec_name,sample_rate,channels", "-of", "json", str(path),
            ]))
            stream = info["streams"][0]
            self.assertEqual((stream["codec_name"], stream["sample_rate"], stream["channels"]),
                             ("vorbis", "48000", 2))
            self.assertGreaterEqual(float(info["format"]["duration"]), 0.4)
            self.assertLess(float(info["format"]["duration"]), 0.9)
            loudness, peak = voice.audio_levels(path)
            self.assertGreater(loudness, -60)
            self.assertLessEqual(peak, -1)

    def test_failed_second_synthesis_preserves_the_installed_set(self):
        def synthesize(text, target):
            if text == voice.WORDS[2]:
                raise OSError("Synthesis service unavailable")
            voice.ffmpeg("-i", str(ADDON_ROOT / "Media/Sounds/Countdown_3.ogg"), str(target))

        with tempfile.TemporaryDirectory() as scratch:
            folder = Path(scratch)
            original = {f"Countdown_{number}.ogg": f"installed-{number}".encode() for number in (3, 2, 1)}
            for name, content in original.items():
                (folder / name).write_bytes(content)
            with patch.object(voice, "OUTPUT_DIR", folder), patch.object(voice, "synthesize", synthesize):
                with self.assertRaises(OSError):
                    voice.main()
            self.assertEqual({path.name: path.read_bytes() for path in folder.iterdir()}, original)


if __name__ == "__main__":
    unittest.main()
