#!/usr/bin/env python3
"""Render original mono mushi calls with drifting resonances and glass tones.

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
    gust_depth: float = .24
    band_sway: float = 0.0
    tone_mix: float = 0.0  # 0 preserves the earlier noise-excited auditions.
    pulse_depth: float = 0.0


VOICES = {
    # The lower Q versions keep the colored-noise breath especially audible.
    "hollow": Voice(240, 6.5, (1, 1.5, 2, 3), (1, .7, .52, .29), .027, .36, .33),
    "airy": Voice(310, 3.4, (1, 1.5, 2, 3, 4), (1, .75, .55, .32, .15), .043, .43, .42),
    # Close, slowly breathing resonances from ~540 to 2700 Hz. The stronger
    # upper partials make these read as small hollow objects, not a low wind bed.
    "glassy": Voice(540, 32, (1, 1.5, 2, 3, 4, 5),
                    (.52, .62, .83, .72, .48, .29), .007, .17, .23, .08, .12),
    "glassy_soft": Voice(505, 25, (1, 1.5, 2, 3, 4, 5.5),
                         (.65, .70, .82, .59, .34, .17), .008, .20, .19, .10, .10),
    "glassy_etched": Voice(570, 43, (1, 1.5, 2, 3, 4, 5),
                           (.37, .55, .77, .83, .63, .41), .005, .12, .29, .06, .15),
    # Glass harp auditions: mostly sustained, slowly drifting tones. The
    # remaining bandpass excitation gives the harmonics a little texture.
    "glass_harp_soft": Voice(505, 82, (1, 1.5, 2, 3, 4, 5.5),
                             (.65, .70, .82, .59, .34, .17), .0045, .30,
                             .19, .03, 0, .90, .67),
    "glass_harp_bloom": Voice(505, 70, (1, 1.5, 2, 3, 4, 5.5),
                              (.65, .70, .82, .59, .34, .17), .0055, .37,
                              .19, .03, 0, .83, .82),
    "glass_harp_clear": Voice(505, 108, (1, 1.5, 2, 3, 4, 5.5),
                              (.65, .70, .82, .59, .34, .17), .0035, .25,
                              .19, .03, 0, .96, .58),
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
    # Different slow rates and phases keep each partial's amplitude and width
    # from rising together. Two oscillators per control are deterministic but
    # irregular enough to avoid an obvious repeated tremolo.
    gain_rates = [(rng.uniform(.12, .31), rng.uniform(.31, .57)) for _ in range(bands)]
    gain_phases = [(rng.uniform(0, 2 * math.pi), rng.uniform(0, 2 * math.pi))
                   for _ in range(bands)]
    width_rates = [(rng.uniform(.09, .23), rng.uniform(.27, .46)) for _ in range(bands)]
    width_phases = [(rng.uniform(0, 2 * math.pi), rng.uniform(0, 2 * math.pi))
                    for _ in range(bands)]
    tone_phases = [rng.uniform(0, 2 * math.pi) for _ in range(bands)]
    tone_steps = [0.0] * bands
    tone_gains = [1.0] * bands
    tone_gain_steps = [0.0] * bands
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
                if voice.tone_mix:
                    w1, w2 = width_rates[band]
                    p1, p2 = width_phases[band]
                    width = .62 * math.sin(2 * math.pi * w1 * future + p1) + \
                            .38 * math.sin(2 * math.pi * w2 * future + p2)
                    g1, g2 = gain_rates[band]
                    h1, h2 = gain_phases[band]
                    motion = .62 * math.sin(2 * math.pi * g1 * future + h1) + \
                             .38 * math.sin(2 * math.pi * g2 * future + h2)
                    # Square a 0..1 LFO to dwell near silence, while leaving
                    # a small floor so a partial can quietly reappear.
                    target_gain = .06 + .94 * (1 - voice.pulse_depth *
                                                 (.5 - .5 * motion)) ** 2
                    tone_gain_steps[band] = (target_gain - tone_gains[band]) / CONTROL_FRAMES
                    tone_steps[band] = 2 * math.pi * hz / RATE
                else:
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
            if voice.tone_mix:
                tone_phases[band] += tone_steps[band]
                tone_gains[band] += tone_gain_steps[band]
                # Equalize the narrow noise bands against the sine signal:
                # their raw level falls as Q rises. They remain a quiet edge.
                texture = y * math.sqrt(voice.q) * 2.0
                value += voice.weights[band] * tone_gains[band] * (
                    voice.tone_mix * math.sin(tone_phases[band]) +
                    (1 - voice.tone_mix) * texture)
            else:
                shimmer = 1 + voice.band_sway * math.sin(
                    2 * math.pi * (.37 + .071 * band) * t + phases[band])
                value += voice.weights[band] * shimmer * y

        gust = (1 - voice.gust_depth) + voice.gust_depth * math.sin(
            2 * math.pi * voice.gust_hz * t - .7)
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
