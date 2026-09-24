#!/usr/bin/env python3
"""Audition two-tone glass calls modeled on 382286 at 1:26-1:33.

The output is original synthesis, not a copy of the Freesound recording.
The measured pair is approximately 649.5 and 986.38 Hz. This script keeps
the upper note about 13 dB stronger and avoids the many strong partials in
the earlier mushi auditions.

    python scripts/generate_reference_fifth.py
"""

from __future__ import annotations

import argparse
import math
import random
from pathlib import Path

from generate_mushi_audio import PEAK, RATE, save


BASE_HZ = (649.5, 986.38)
UPPER_GAIN = 10 ** (13.1 / 20)


def render(duration: float, seed: int, variant: str) -> list[float]:
    rng = random.Random(seed)
    count = round(RATE * duration)
    phase = [rng.uniform(0, 2 * math.pi) for _ in BASE_HZ]
    # Independent irregular motion. The common component maintains the
    # recognizable fifth while each contact wanders slightly on its own.
    slow_phase = [rng.uniform(0, 2 * math.pi) for _ in BASE_HZ]
    fast_phase = [rng.uniform(0, 2 * math.pi) for _ in BASE_HZ]
    amp_phase = [rng.uniform(0, 2 * math.pi) for _ in BASE_HZ]
    pulse_phase = rng.uniform(0, 2 * math.pi)
    samples: list[float] = []

    for frame in range(count):
        t = frame / RATE
        common = math.sin(2 * math.pi * .17 * t + .4)
        value = 0.0
        for note, hz in enumerate(BASE_HZ):
            private = (.72 * math.sin(2 * math.pi * (.27 + .05 * note) * t + slow_phase[note])
                       + .28 * math.sin(2 * math.pi * (.67 + .07 * note) * t + fast_phase[note]))
            excursion = 1.1 if variant == "close" else (2.1 if variant == "living" else 1.45)
            instantaneous_hz = hz + excursion * (.25 * common + .75 * private)
            phase[note] += 2 * math.pi * instantaneous_hz / RATE
            breath = (.68 * math.sin(2 * math.pi * (.22 + .035 * note) * t + amp_phase[note])
                      + .32 * math.sin(2 * math.pi * (.43 + .07 * note) * t + slow_phase[note]))
            # The rubbing contact makes ~2.9 Hz pulses. Opposing phases let
            # the low and high notes trade emphasis, as in the reference.
            pulse = math.sin(2 * math.pi * (2.9 * t +
                             .09 * math.sin(2 * math.pi * .31 * t + pulse_phase)) +
                             (0 if note == 0 else math.pi) +
                             .17 * math.sin(2 * math.pi * .39 * t + amp_phase[note]))
            slow_db = (5.0 if note == 0 else 3.0) if variant == "close" else (6.0 if note == 0 else 4.0)
            pulse_db = (6.0 if note == 0 else 5.0) if variant == "close" else (7.0 if note == 0 else 6.0)
            amplitude = 10 ** (-(slow_db * (.5 - .5 * breath) +
                                 pulse_db * (.5 - .5 * pulse)) / 20)
            # In the staggered version, let the two contacts emerge separately.
            onset = (.035 + note * .24) if variant == "staggered" else .035
            attack = min(1.0, max(0.0, (t - onset) / .16))
            tone = math.sin(phase[note])
            harmonic = (.014 if note == 0 else .007) if variant == "close" else \
                       (.020 if variant == "living" else .014)
            tone += harmonic * math.sin(2 * phase[note] + .3 * note)
            if note == 1 and variant == "close":
                tone += .004 * math.sin(3 * phase[note] + .8)
            value += (1.0 if note == 0 else UPPER_GAIN) * amplitude * attack * tone

        fade = min(1.0, max(0.0, (duration - t) / .7))
        samples.append(value * fade)

    maximum = max(abs(sample) for sample in samples)
    return [sample * PEAK / maximum for sample in samples]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--duration", type=float, default=7.0)
    parser.add_argument("--seed", type=int, default=382286)
    parser.add_argument("--output-dir", type=Path,
                        default=Path(".local/audio-auditions-reference-synth"))
    args = parser.parse_args()
    if not .5 <= args.duration <= 30:
        parser.error("--duration must be between 0.5 and 30 seconds")
    for variant in ("close", "living", "staggered"):
        path = args.output_dir / f"mushi_reference_{variant}.wav"
        save(path, render(args.duration, args.seed, variant))
        print(path)


if __name__ == "__main__":
    main()
