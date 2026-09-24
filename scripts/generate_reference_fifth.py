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
BRIGHT_VARIANTS = ("etched", "reese", "friction")


def render(duration: float, seed: int, variant: str,
           root_hz: float = BASE_HZ[0],
           interval_ratio: float = BASE_HZ[1] / BASE_HZ[0]) -> list[float]:
    """Render one call; pass 4/3 or 3/2 for a fourth or fifth palette."""
    frequencies = (root_hz, root_hz * interval_ratio)
    rng = random.Random(seed)
    count = round(RATE * duration)
    phase = [rng.uniform(0, 2 * math.pi) for _ in frequencies]
    # Independent irregular motion. The common component maintains the
    # recognizable fifth while each contact wanders slightly on its own.
    slow_phase = [rng.uniform(0, 2 * math.pi) for _ in frequencies]
    fast_phase = [rng.uniform(0, 2 * math.pi) for _ in frequencies]
    amp_phase = [rng.uniform(0, 2 * math.pi) for _ in frequencies]
    pulse_phase = rng.uniform(0, 2 * math.pi)
    bright = variant in BRIGHT_VARIANTS
    # Contact friction is high-passed so it adds a fine edge without changing
    # the two-note center. Keep this state separate from the pitch motion.
    friction_low = 0.0
    friction_alpha = 1.0 - math.exp(-2 * math.pi * 3200 / RATE)
    resonance_phase = [0.0, .7]
    samples: list[float] = []

    for frame in range(count):
        t = frame / RATE
        common = math.sin(2 * math.pi * .17 * t + .4)
        value = 0.0
        for note, hz in enumerate(frequencies):
            private = (.72 * math.sin(2 * math.pi * (.27 + .05 * note) * t + slow_phase[note])
                       + .28 * math.sin(2 * math.pi * (.67 + .07 * note) * t + fast_phase[note]))
            excursion = 1.1 if variant == "close" or bright else (2.1 if variant == "living" else 1.45)
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
            slow_db = (5.0 if note == 0 else 3.0) if variant == "close" or bright else (6.0 if note == 0 else 4.0)
            pulse_db = (6.0 if note == 0 else 5.0) if variant == "close" or bright else (7.0 if note == 0 else 6.0)
            amplitude = 10 ** (-(slow_db * (.5 - .5 * breath) +
                                 pulse_db * (.5 - .5 * pulse)) / 20)
            # In the staggered version, let the two contacts emerge separately.
            onset = (.035 + note * .24) if variant == "staggered" else .035
            attack = min(1.0, max(0.0, (t - onset) / .16))
            tone = math.sin(phase[note])
            if variant == "reese" and note == 1:
                tone += .16 * math.sin(phase[note] - 2 * math.pi * 2.0 * t + .5)
            harmonic = (.014 if note == 0 else .007) if variant == "close" else \
                       (.020 if variant == "living" else .014)
            if bright:
                harmonic = .028 if note == 0 else .013
            tone += harmonic * math.sin(2 * phase[note] + .3 * note)
            if note == 1 and variant == "close":
                tone += .004 * math.sin(3 * phase[note] + .8)
            if bright and note == 1:
                # Sparse glass/contact partials. These deliberately remain
                # tens of dB below the upper fundamental, unlike a saw wave.
                partials = ((3, .008), (4, .004), (5, .0045),
                            (6, .0025), (7, .0018))
                for multiple, gain in partials:
                    angle = multiple * phase[note] + .31 * multiple
                    if variant == "reese":
                        # Small moving sidebands create the soft beating edge
                        # of two detuned contacts; the main pitch stays put.
                        side = 2 * math.pi * (1.8 + .17 * multiple) * t
                        partial = (.82 * math.sin(angle) +
                                   .41 * math.sin(angle + side) +
                                   .41 * math.sin(angle - .73 * side))
                    else:
                        partial = math.sin(angle)
                    tone += gain * partial
            value += (1.0 if note == 0 else UPPER_GAIN) * amplitude * attack * tone

        fade = min(1.0, max(0.0, (duration - t) / .7))
        if bright:
            # Independent, mobile contact resonances around 6.5 and 9.1 kHz.
            # Their level drifts over seconds, as do the bright clusters in
            # the reference; neither is locked to an exact harmonic.
            resonance_motion = (14 * math.sin(2 * math.pi * .23 * t + .2) +
                                4 * math.sin(2 * math.pi * .61 * t + .8))
            resonance_phase[0] += 2 * math.pi * (root_hz * 10 + 21 + resonance_motion) / RATE
            resonance_phase[1] += 2 * math.pi * (root_hz * 14 + 19 + .7 * resonance_motion) / RATE
            shimmer = .15 + .85 * (.5 + .5 * math.sin(2 * math.pi * .23 * t + .3)) ** 2
            contact = min(1.0, t / .19) * shimmer
            value += contact * (.038 * math.sin(resonance_phase[0]) +
                                .012 * math.sin(resonance_phase[1]))
            white = rng.uniform(-1.0, 1.0)
            friction_low += friction_alpha * (white - friction_low)
            noise_gain = {"etched": .013, "reese": .010,
                          "friction": .045}[variant]
            grain = .68 + .32 * math.sin(2 * math.pi * 2.9 * t + pulse_phase)
            value += noise_gain * grain * (white - friction_low) * min(1.0, t / .19)
        samples.append(value * fade)

    maximum = max(abs(sample) for sample in samples)
    return [sample * PEAK / maximum for sample in samples]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--duration", type=float, default=7.0)
    parser.add_argument("--seed", type=int, default=382286)
    parser.add_argument("--bright", action="store_true",
                        help="render three restrained high-frequency edge variants")
    parser.add_argument("--root-hz", type=float, default=BASE_HZ[0])
    parser.add_argument("--interval", choices=("reference", "fourth", "fifth"),
                        default="reference")
    parser.add_argument("--output-dir", type=Path,
                        default=None)
    args = parser.parse_args()
    if not .5 <= args.duration <= 30:
        parser.error("--duration must be between 0.5 and 30 seconds")
    if not 80 <= args.root_hz <= 3000:
        parser.error("--root-hz must be between 80 and 3000 Hz")
    ratio = {"reference": BASE_HZ[1] / BASE_HZ[0],
             "fourth": 4 / 3, "fifth": 3 / 2}[args.interval]
    frequencies = (args.root_hz, args.root_hz * ratio)
    if frequencies[1] * 7 >= RATE / 2:
        parser.error("pitch is too high for the seventh partial at 48 kHz")
    output_dir = args.output_dir or Path(
        ".local/audio-auditions-bright" if args.bright else
        ".local/audio-auditions-reference-synth")
    variants = BRIGHT_VARIANTS if args.bright else ("close", "living", "staggered")
    audition_rms = None
    for variant in variants:
        path = output_dir / f"mushi_reference_{variant}.wav"
        samples = render(args.duration, args.seed, variant, args.root_hz, ratio)
        if args.bright:
            # Match perceived audition level to etched. The Reese version
            # has a slightly higher crest factor due to beating.
            rms = math.sqrt(sum(sample * sample for sample in samples) / len(samples))
            audition_rms = rms if audition_rms is None else audition_rms
            samples = [sample * audition_rms / rms for sample in samples]
        save(path, samples)
        print(path)


if __name__ == "__main__":
    main()
