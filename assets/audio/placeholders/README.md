# Procedural audio placeholders

These are original, deterministic placeholder sounds generated offline by
[`scripts/generate_audio_placeholders.py`](../../../scripts/generate_audio_placeholders.py).
They use only Python's standard library. Regenerate from the repository root with:

```sh
python scripts/generate_audio_placeholders.py
```

All files are mono 48 kHz, signed 16-bit PCM WAV. The generator limits each
asset's peak to 0.18 full scale (about -14.9 dBFS); source gain in the game
should still be mixed by ear. These synthetic placeholders are for implementation
and spatial routing, not final sound design. The forest beds are short loopable
texture sources; check loop boundaries and subjective looping before release.

| Prefix / name | Intended cue | Duration |
| --- | --- | ---: |
| `mushi_resonance_01..04` | Sparse resonant wind/noise calls | 1.20–1.55 s |
| `forest_insects_01..03` | Localized insect/cricket beds | 3.20 s |
| `footstep_ground_01..04` | Grounded soft thump/crunch variants | 0.32 s |
| `lantern_flame_bed` | Quiet filtered flame texture | 4.00 s |
| `lantern_rope_creak_01..02` | Soft rope/fiber creaks | 0.80 s |
| `lantern_metal_swing_01..02` | Restrained metallic swing ticks | 0.62 s |
| `shutter_detent_01..03` | Short shutter/filter control detents | 0.14 s |
| `filter_detent_01..02` | Short filter control detents | 0.14 s |

There are no third-party samples or external assets in this set.
