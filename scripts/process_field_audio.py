#!/usr/bin/env python3
"""Rebuild mono field recordings from the six CC0 Freesound downloads.

Requires FFmpeg (prepared with 9.0.1). Source files are looked up by their
Freesound ID in ~/Downloads and checked against the hashes below.
"""

from __future__ import annotations

import hashlib
from pathlib import Path
import shutil
import subprocess
import wave


ROOT = Path(__file__).resolve().parents[1]
DOWNLOADS = Path.home() / "Downloads"
OUTPUT = ROOT / "assets/audio/field"

# ID: SHA-256 of the downloaded, unmodified source recording.
SOURCES = {
    "320145": "d7678f7259af893dcb41ea633eb934fed7b8cf0f116b053fb7a96552babf690a",
    "453862": "b26328f870206cb362dc5c7b80ca8a5b4faf1550f60a6d3fc8c11e229193c90b",
    "398685": "d9f740ee4097f15022e3ec59d0e60de30b8aa9e6eabfbcd3e63931f633ec7e73",
    "411530": "b4ca7ea67c6db97e5b77b40d90fd9e83c1d535b45cc4ef26cf10cc1b5a1f31c5",
    "516740": "819a9a7f7d58e6ef0db2da86b6846927cd5990e71254c2d7833a1d468bedf8e3",
    "622854": "237c93d7a175e5ae35b8593135323eaa541ac4ca22eebc9ad0d1ebe039ec57bd",
}

# output name, source ID, start/end seconds, gain in dB, fade in/out seconds.
CLIPS = (
    ("forest_crickets_owl.wav", "320145", 0.0, 40.0, 7.0, 0.25, 0.25),
    ("forest_cicadas_kyles.wav", "453862", 0.0, 35.35, 13.0, 0.25, 0.25),
    ("footsteps_foliage.wav", "398685", 0.0, 11.8, 3.0, 0.12, 0.12),
    ("lantern_swing.wav", "411530", 0.1, 6.65, 12.0, 0.12, 0.12),
    ("lantern_shutter_open.wav", "516740", 3.7, 4.65, -9.0, 0.025, 0.07),
    ("lantern_shutter_close.wav", "516740", 14.65, 15.6, -9.0, 0.025, 0.07),
    ("lantern_wick.wav", "622854", 20.0, 38.0, -2.0, 0.2, 0.2),
)


def source_path(sound_id: str) -> Path:
    matches = list(DOWNLOADS.glob(f"{sound_id}__*"))
    if len(matches) != 1:
        raise RuntimeError(f"Expected exactly one download for {sound_id}, found {matches}")
    path = matches[0]
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if digest != SOURCES[sound_id]:
        raise RuntimeError(f"Source hash changed for {path}: {digest}")
    return path


def main() -> None:
    if not shutil.which("ffmpeg"):
        raise RuntimeError("FFmpeg is required")
    inputs = {sound_id: source_path(sound_id) for sound_id in SOURCES}
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for name, sound_id, start, end, gain, fade_in, fade_out in CLIPS:
        duration = end - start
        filters = (
            f"atrim=start={start}:end={end},asetpts=PTS-STARTPTS,"
            f"volume={gain}dB,"
            f"afade=t=in:st=0:d={fade_in},"
            f"afade=t=out:st={duration - fade_out}:d={fade_out}"
        )
        output = OUTPUT / name
        subprocess.run(
            ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(inputs[sound_id]),
             "-af", filters, "-ac", "1", "-ar", "48000", "-c:a", "pcm_s16le", str(output)],
            check=True,
        )
        with wave.open(str(output), "rb") as wav:
            assert (wav.getnchannels(), wav.getframerate(), wav.getsampwidth()) == (1, 48000, 2)
            print(f"{name}: {wav.getnframes() / 48000:.3f}s, {output.stat().st_size} bytes")


if __name__ == "__main__":
    main()
