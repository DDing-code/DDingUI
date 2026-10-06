"""Synthesize the original three-second Time Rewind sound; no external samples.

python DDingUI_FX/tools/build_time_rewind_sound.py
Uses the installed NumPy/SciPy/FFmpeg. Stages WAV/MP3 for inspection.
"""
from pathlib import Path
from hashlib import sha256
import json
import subprocess

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt, resample_poly

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'artifacts/DDingUI_FX/audio/time-rewind'
SR, DURATION = 48000, 3


def band(samples, low, high):
    return sosfilt(butter(2, [low, high], btype='bandpass', fs=SR, output='sos'), samples)


def bell(hz, duration, decay):
    t = np.arange(round(duration * SR)) / SR
    wave = sum(amp * np.sin(2*np.pi*hz*ratio*t + phase) * np.exp(-t*decay*(1 + j*.22))
               for j, (ratio, amp, phase) in enumerate(zip(
                   (1, 1.503, 2.397, 3.771, 5.183), (1, .38, .19, .08, .03), (0, .7, 1.4, .2, 1.1))))
    wave *= np.minimum(1, t/.0025)
    wave *= np.minimum(1, (duration-t)/.018)
    return wave


def render():
    rng = np.random.default_rng(20260926)
    count = SR * DURATION
    t = np.arange(count) / SR
    mix = np.zeros((count, 2), dtype=float)

    def add(samples, start, gain=1, pan=0):
        index = round(start*SR)
        assert index >= 0
        samples = samples[:count-index] * gain
        p = (np.asarray(pan) + 1) * np.pi/4
        gains = np.stack((np.cos(p), np.sin(p)), axis=-1)
        mix[index:index+len(samples)] += samples[:, None] * gains

    # Gathering light: reverse bell swell resolves as the clock finishes forming.
    add(bell(659.255, .53, 7)[::-1], .015, .30, -.18)
    add(bell(987.767, .39, 10)[::-1], .15, .11, .25)
    add(bell(659.255, 1.15, 5.3), .535, .32)

    # Warm rewind bed, with air following the particle orbit across stereo space.
    rise = np.clip(t/.5, 0, 1)**1.5
    end = np.clip((2.9-t)/.50, 0, 1)**1.4
    air = band(rng.standard_normal(count), 340, 5100)
    air /= np.std(air)
    air *= rise * end * (.75 + .25*np.sin(2*np.pi*1.6*t))
    add(air, 0, .038, .32*np.sin(2*np.pi*.55*t))
    hz = 178 - 45*np.clip(t/2.6, 0, 1) + 3.5*np.sin(2*np.pi*5.2*t)
    phase = 2*np.pi*np.cumsum(hz)/SR
    hum = (np.sin(phase) + .22*np.sin(2.01*phase) + .10*np.sin(3.003*phase))
    hum *= rise * end * (.8 + .2*np.sin(2*np.pi*8*t))
    add(hum, 0, .052)

    # Twelve reversed escapement ticks: swelling resonance, then a delicate snap.
    for j in range(12):
        hit = .60 + j*.15
        reverse = bell(1430 if j % 2 == 0 else 1680, .105, 34)[::-1]
        add(reverse, hit-.105, .13, .30*np.sin(j*.85))
        tick_t = np.arange(round(.035*SR))/SR
        snap = band(rng.standard_normal(len(tick_t)), 1250, 6500)
        snap *= np.exp(-tick_t*190) * np.minimum(1, tick_t/.001)
        add(snap, hit, .08, -.20*np.sin(j*.85))

    # Small glass fragments follow the circulating light; no melody or speech.
    for j, start in enumerate(np.linspace(.22, 2.44, 18)):
        grain = bell((1318.51, 1975.53, 2637.02)[j % 3], .135, 28)
        add(grain[::-1], float(start), .025 + .012*(j % 2), .52*np.sin(j*1.7))

    # Inward recall: a soft descending pressure sweep with a short closing chime.
    tail_t = np.arange(round(.58*SR))/SR
    sweep_hz = 460 * np.exp(-tail_t*4.4)
    sweep = np.sin(2*np.pi*np.cumsum(sweep_hz)/SR)
    envelope = np.sin(np.pi*tail_t/.58)**1.4
    noise = band(rng.standard_normal(len(tail_t)), 190, 2700)
    add((.09*sweep + .10*noise) * envelope, 2.36)
    add(bell(1108.73, .21, 23), 2.765, .10)

    # Restrained, dark stereo room reflections; the final release ends at 3 s.
    dry = mix.copy()
    for delay, gain in ((.027, .10), (.061, .075), (.103, .055), (.173, .032), (.251, .018)):
        n = round(delay*SR)
        for ch in range(2):
            echo = band(dry[:, 1-ch], 180, 4200)
            mix[n:, ch] += echo[:-n] * gain
    mix = sosfilt(butter(2, 45, btype='highpass', fs=SR, output='sos'), mix, axis=0)
    mix = np.tanh(mix*1.3)
    mix *= (np.sin(np.clip(t/.012, 0, 1)*np.pi/2)**2)[:, None]
    mix *= (np.sin(np.clip((DURATION-t)/.11, 0, 1)*np.pi/2)**2)[:, None]
    # Normalize against 4x oversampled peak, leaving MP3 encoding headroom.
    peak = np.max(np.abs(resample_poly(mix, 4, 1, axis=0)))
    mix *= 10**(-2.5/20)/peak
    assert mix.shape == (144000, 2) and np.isfinite(mix).all()
    assert np.max(np.abs(mix[0])) < 1e-6 and np.max(np.abs(mix[-1])) < 1e-6
    return mix


def build():
    OUT.mkdir(parents=True, exist_ok=True)
    signal = render()
    wav, mp3 = OUT/'DD_Time_Rewind.wav', OUT/'DD_Time_Rewind.mp3'
    wavfile.write(wav, SR, np.rint(signal*32767).astype(np.int16))
    subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-i', str(wav),
                    '-codec:a', 'libmp3lame', '-b:a', '192k', '-ar', str(SR),
                    '-metadata', 'title=DD_Time Rewind', str(mp3)], check=True)
    decoded = subprocess.run(['ffmpeg', '-v', 'error', '-i', str(mp3), '-f', 'f32le',
                              '-acodec', 'pcm_f32le', '-ar', str(SR), '-ac', '2', '-'],
                             check=True, capture_output=True).stdout
    decoded = np.frombuffer(decoded, dtype='<f4').reshape(-1, 2)
    assert decoded.shape == signal.shape and np.isfinite(decoded).all()
    true_peak = 20*np.log10(np.max(np.abs(resample_poly(decoded, 4, 1, axis=0))))
    rms = 20*np.log10(np.sqrt(np.mean(decoded**2)))
    assert true_peak < -1 and -24 < rms < -10, (true_peak, rms)
    assert np.max(np.abs(decoded.mean(axis=0))) < .001
    assert np.sqrt(np.mean(decoded[-240:]**2)) < .001
    assert all(np.sqrt(np.mean(decoded[i:i+4800]**2)) > .005 for i in range(4800, 124800, 4800))
    report = dict(name='DD_Time Rewind', duration_seconds=3, sample_rate=SR, channels=2,
                  bitrate_kbps=192, synthesis='original local DSP; no speech model or external samples',
                  timing={'gather_and_chime': [0, .55], 'rewind_ticks': [.6, 2.25], 'recall': [2.36, 3]},
                  decoded_true_peak_dbfs=float(true_peak), decoded_rms_dbfs=float(rms),
                  mp3_sha256=sha256(mp3.read_bytes()).hexdigest(),
                  status='staged; actual WoW audio output unverified')
    (OUT/'manifest.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    build()
