#!/usr/bin/env python3
"""Generate deterministic, original mono WAV placeholders for Mushi Lantern.

Uses only Python's standard library. Run from any directory; outputs land under
assets/audio/placeholders relative to this script. Files are 48 kHz, mono,
16-bit PCM, with conservative peak normalization to 0.18 full scale.
"""
from __future__ import annotations

import math
import argparse
import random
import struct
import wave
from pathlib import Path

from generate_reference_fifth import BASE_HZ, render as render_glass_pair

RATE = 48_000
PEAK_LIMIT = 0.18
OUT = Path(__file__).resolve().parents[1] / "assets/audio/placeholders"
EXPECTED = [
    *(f"mushi_resonance_{i:02d}.wav" for i in range(1, 5)),
    *(f"forest_insects_{i:02d}.wav" for i in range(1, 4)),
    *(f"footstep_ground_{i:02d}.wav" for i in range(1, 5)),
    "lantern_flame_bed.wav",
    *(f"lantern_rope_creak_{i:02d}.wav" for i in range(1, 3)),
    *(f"lantern_metal_swing_{i:02d}.wav" for i in range(1, 3)),
    *(f"shutter_detent_{i:02d}.wav" for i in range(1, 4)),
    *(f"filter_detent_{i:02d}.wav" for i in range(1, 3)),
]


def smooth_noise(n: int, seed: int, stride: int = 90) -> list[float]:
    """Linearly interpolated random control noise, softly band-limited in spirit."""
    rng = random.Random(seed)
    points = [rng.uniform(-1.0, 1.0) for _ in range(n // stride + 2)]
    return [points[i // stride] * (1 - (i % stride) / stride) + points[i // stride + 1] * ((i % stride) / stride) for i in range(n)]


def write(name: str, samples: list[float]) -> None:
    peak = max((abs(x) for x in samples), default=0.0)
    scale = min(1.0, PEAK_LIMIT / peak) if peak else 1.0
    pcm = bytearray()
    for x in samples:
        value = int(max(-1.0, min(1.0, x * scale)) * 32767)
        pcm.extend(struct.pack("<h", value))
    path = OUT / f"{name}.wav"
    with wave.open(str(path), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(pcm)


def insect(seed: int, rate_hz: float, tone: float) -> list[float]:
    length = 3.2
    n = int(RATE * length)
    noise = smooth_noise(n, seed, 22)
    out = []
    for i in range(n):
        t = i / RATE
        phase_in_call = (t * rate_hz) % 1.0
        gate = max(0.0, min(1.0, phase_in_call / 0.11, (0.30 - phase_in_call) / 0.08))
        chirp = math.sin(2 * math.pi * (tone + 95 * phase_in_call) * t)
        out.append(gate * (0.75 * chirp + 0.25 * noise[i]) * (0.68 + 0.32 * math.sin(2 * math.pi * 0.23 * t)))
    return out


def footstep(seed: int, pitch: float, grit: float) -> list[float]:
    length = 0.32
    n = int(RATE * length)
    noise = smooth_noise(n, seed, 7)
    rng = random.Random(seed + 900)
    out = []
    for i in range(n):
        t = i / RATE
        thump = math.sin(2 * math.pi * pitch * t) * math.exp(-t * 23)
        crunch = noise[i] * math.exp(-t * 34) * (0.45 + 0.55 * rng.random())
        out.append((0.8 * thump + grit * crunch) * min(1.0, t / 0.003))
    return out


def flame(seed: int) -> list[float]:
    length = 4.0
    n = int(RATE * length)
    noise = smooth_noise(n, seed, 15)
    finer = smooth_noise(n, seed + 7, 3)
    out = []
    for i in range(n):
        t = i / RATE
        slow = 0.52 + 0.12 * math.sin(2 * math.pi * 0.31 * t) + 0.08 * math.sin(2 * math.pi * 0.73 * t + 1)
        out.append((noise[i] * 0.75 + finer[i] * 0.25) * slow)
    return out


def creak(seed: int, tone: float, metallic: bool) -> list[float]:
    length = 0.62 if metallic else 0.8
    n = int(RATE * length)
    noise = smooth_noise(n, seed, 12)
    out = []
    for i in range(n):
        t = i / RATE
        u = t / length
        f = tone * (1 + (0.10 if metallic else 0.05) * math.sin(2 * math.pi * (1.4 if metallic else 0.8) * t))
        tonepart = math.sin(2 * math.pi * f * t) + 0.26 * math.sin(2 * math.pi * f * 2.73 * t)
        weight = math.sin(math.pi * u) ** 1.3
        out.append((tonepart * (0.72 if metallic else 0.42) + noise[i] * (0.13 if metallic else 0.38)) * weight)
    return out


def detent(seed: int, pitch: float) -> list[float]:
    length = 0.14
    n = int(RATE * length)
    noise = smooth_noise(n, seed, 4)
    return [(0.72 * math.sin(2 * math.pi * pitch * (i / RATE)) + 0.28 * noise[i]) * math.exp(-i / RATE * 38) for i in range(n)]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--if-missing", action="store_true", help="Generate only when an expected WAV is absent")
    args = parser.parse_args()
    if args.if_missing and all((OUT / name).is_file() for name in EXPECTED):
        return
    OUT.mkdir(parents=True, exist_ok=True)
    # Two fourths and two fifths, with small tuning differences like separate
    # pieces of glass. The contact texture adds an insect-like edge without
    # the detuned beating; avoid thirds, which color the harmony too strongly.
    calls = (
        (3.1, 649.5, BASE_HZ[1] / BASE_HZ[0]),
        (2.9, 610.0, 1.336),
        (3.0, 690.0, 1.497),
        (3.2, 575.0, 1.330),
    )
    for i, (length, root_hz, ratio) in enumerate(calls, 1):
        write(f"mushi_resonance_{i:02d}",
              render_glass_pair(length, 100 + i, "friction", root_hz, ratio))
    for i, (hz, tone) in enumerate([(3.2, 3900), (4.1, 4450), (2.7, 3500)], 1):
        write(f"forest_insects_{i:02d}", insect(200 + i, hz, tone))
    for i, (pitch, grit) in enumerate([(92, .38), (118, .31), (76, .46), (105, .42)], 1):
        write(f"footstep_ground_{i:02d}", footstep(300 + i, pitch, grit))
    write("lantern_flame_bed", flame(410))
    for i, tone in enumerate([205, 287], 1):
        write(f"lantern_rope_creak_{i:02d}", creak(500 + i, tone, False))
    for i, tone in enumerate([740, 980], 1):
        write(f"lantern_metal_swing_{i:02d}", creak(510 + i, tone, True))
    for i, pitch in enumerate([1250, 1680, 2050], 1):
        write(f"shutter_detent_{i:02d}", detent(600 + i, pitch))
    for i, pitch in enumerate([930, 1120], 1):
        write(f"filter_detent_{i:02d}", detent(700 + i, pitch))


if __name__ == "__main__":
    main()
