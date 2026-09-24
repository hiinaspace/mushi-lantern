#!/usr/bin/env python3
"""Render original mono mushi calls: noise through drifting resonant bandpasses.

No external packages. The files are auditions, not installed game assets.

    python scripts/generate_mushi_audio.py
    python scripts/generate_mushi_audio.py --profile airy --duration 3 --seed 42
    python scripts/generate_mushi_audio.py --output-dir /path/to/auditions
"""

from __future__ import annotations

import argparse
import math
import random
import struct
import tempfile
import wave
from dataclasses import dataclass
from pathlib import Path


RATE = 48_000
PEAK = 0.22
CONTROL_FRAMES = 96  # 500 control points/s; coefficients interpolate per audio frame.


@dataclass(frozen=True)
class Voice:
    root_hz: float
    q: float
    ratios: tuple[float, ...]
    weights: tuple[float, ...]
    drift: float
    q_sway: float
    gust_hz: float


VOICES = {
    # The lower Q versions keep the colored-noise breath especially audible.
    "hollow": Voice(240, 6.5, (1, 1.5, 2, 3), (1, .7, .52, .29), .027, .36, .33),
    "airy": Voice(310, 3.4, (1, 1.5, 2, 3, 4), (1, .75, .55, .32, .15), .043, .43, .42),
    "glassy": Voice(275, 10, (1, 1.5, 2, 3), (1, .65, .46, .24), .018, .29, .27),
}


def coefficients(hz: float, q: float) -> tuple[float, float, float, float, float]:
    """RBJ constant 0 dB peak bandpass; bandwidth changes with Q."""
    omega = 2 * math.pi * hz / RATE
    alpha = math.sin(omega) / (2 * q)
    a0 = 1 + alpha
    return (alpha / a0, 0.0, -alpha / a0,
            -2 * math.cos(omega) / a0, (1 - alpha) / a0)


def render(voice: Voice, duration: float, seed: int) -> list[float]:
    rng = random.Random(seed)
    count = round(RATE * duration)
    bands = len(voice.ratios)
    # Independent broad-band exciters avoid coherent phase cancellation.
    noise_rngs = [random.Random(rng.getrandbits(64)) for _ in range(bands)]
    phases = [rng.uniform(0, 2 * math.pi) for _ in range(bands)]
    q_phases = [rng.uniform(0, 2 * math.pi) for _ in range(bands)]
    states = [[0.0, 0.0, 0.0, 0.0] for _ in range(bands)]
    controls = [list(coefficients(voice.root_hz * ratio, voice.q)) for ratio in voice.ratios]
    steps = [[0.0] * 5 for _ in range(bands)]
    samples = []

    for frame in range(count):
        t = frame / RATE
        if frame % CONTROL_FRAMES == 0:
            future = (frame + CONTROL_FRAMES) / RATE
            for band, ratio in enumerate(voice.ratios):
                # A common slow breath binds the partials; their smaller,
                # independent motion stops them behaving as a rigid chord.
                common = math.sin(2 * math.pi * .19 * future + .6)
                private = math.sin(2 * math.pi * (.31 + .047 * band) * future + phases[band])
                hz = voice.root_hz * ratio * (1 + voice.drift * (.58 * common + .42 * private))
                width = math.sin(2 * math.pi * (.23 + .061 * band) * future + q_phases[band])
                q = voice.q * (1 + voice.q_sway * width)
                target = coefficients(hz, q)
                steps[band] = [(b - a) / CONTROL_FRAMES for a, b in zip(controls[band], target)]

        value = 0.0
        for band in range(bands):
            c = controls[band]
            dc = steps[band]
            for index in range(5):
                c[index] += dc[index]
            x1, x2, y1, y2 = states[band]
            x = noise_rngs[band].uniform(-1, 1)
            y = c[0] * x + c[1] * x1 + c[2] * x2 - c[3] * y1 - c[4] * y2
            states[band] = [x, x1, y, y1]
            value += voice.weights[band] * y

        gust = .76 + .24 * math.sin(2 * math.pi * voice.gust_hz * t - .7)
        fade = min(1.0, t / .055, (duration - t) / .20)
        samples.append(value * gust * max(0.0, fade))

    peak = max(abs(sample) for sample in samples)
    return [sample * (PEAK / peak) for sample in samples]


def save(path: Path, samples: list[float]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    data = struct.pack(f"<{len(samples)}h", *(round(sample * 32767) for sample in samples))
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        wav.writeframes(data)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=["all", *VOICES], default="all")
    parser.add_argument("--duration", type=float, default=2.5, help="seconds per call")
    parser.add_argument("--seed", type=int, default=271828)
    parser.add_argument("--output-dir", type=Path,
                        default=Path(tempfile.gettempdir()) / "mushi-lantern-audio-audition")
    args = parser.parse_args()
    if not .25 <= args.duration <= 30:
        parser.error("--duration must be between 0.25 and 30 seconds")
    names = VOICES if args.profile == "all" else {args.profile: VOICES[args.profile]}
    for name, voice in names.items():
        path = args.output_dir / f"mushi_{name}.wav"
        save(path, render(voice, args.duration, args.seed + list(VOICES).index(name)))
        print(path)


if __name__ == "__main__":
    main()
