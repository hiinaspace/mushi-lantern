# M0 implementation evidence — 2026-09-21

Host: `natto`. Runtime: Godot `4.7.2.stable.official.ed1daf0bf`, Vulkan Mobile on AMD Radeon 780M. See `local-runtime.md` for installation and provenance.

## Passed

- `./check.sh`: **32 simulation checks, zero failures**, plus the isolated UI persistence/reset smoke test. Tests cover field masks, occlusion, filter-switch smoothing, deterministic resets, motion bounds, collision sweep, snapshot updates, blue settling/catch-up, local goal resistance and finite score-once lifecycle. The UI test uses temporary user data and does not overwrite player presets.
- Windowed first-person and top-down scenes rendered successfully. Captures are deterministic camera snapshots, not human gameplay validation. The lamp proxy housing does not cast shadows into its own emitter; trunks still cast shadows and occlude the gameplay field.
- Reviewed the full-size first-person screenshot for control readability and the top-down screenshot for population, obstacles, return circle and sampled field. The arrival disc is separately labeled; influence tiles show the actual radial/angular/occluded field sampled at creature height.
- Corrected stale filter exposure on mode switches, same-step neighbor membership, stale reset events, CLI preset selection, camera reset, and save-buffer flushing. Named presets restore the seed and fixture. Live tuning is timestamped within a run instead of being reported as one unchanged configuration.

Run `./launch.sh --tiny` for the nearby three-creature fixture. Hold Shift for slow leading; F11 enables fullscreen if the desktop tiles the window too small. See the README for all controls and `m0-playtest.md` for the human test card.

## Goal resistance experiment

The user proposed mild goal repulsion to make entry deliberate. Implemented as a smooth, local outward force around the return rim, fading inside and absent from committed/ascending creatures. No global goal attraction, automatic scoring, or required filter switch was added. A slider spans 0–2.5; **0.8 is an unapproved mild starting candidate**, not a selected winner. Zero preserves the original control.

Same seed `40721`, 24 agents, actual three-trunk scene layout, clear/no stimulus, 60 simulated seconds:

| Goal resistance | Plain boids returns | Arousal memory returns | Independent seekers returns |
| --- | ---: | ---: | ---: |
| 0 | 0 | 0 | 9 |
| 0.8 | 0 | 0 | 4 |
| 1.5 | 0 | 0 | 0 |

All runs remained finite and within steering/speed bounds. This is a single-seed diagnostic, not a statistical result. The shorter 12-second unattended checks in the regression suite pass for all presets; those must not be presented as evidence of zero accidental returns over longer play.

A separate scripted crossing fixture placed three agents at `z=3.5` and a stationary lamp at `(0, 1.2, 5)` aimed toward the goal. Over 20 seconds, blue returned 3/3 at both 0.8 and 1.5 resistance; orange returned 3/3 at 0.8 and 2/3 at 1.5. Thus both actions can cross the threshold, but this does not establish how easy or pleasant player delivery is. Default 0.8 still permits accidental returns in independent seekers. Compare it with zero and 1.5 during play.

The initial simulation-only baseline, without scene obstacles or goal resistance, took about 0.43 ms per step for 24 social agents on this laptop. This is a rough local timing, not a full-scene benchmark or VR performance claim.

## Local retained evidence

`artifacts/m0-20260921/` contains renderer/import/check logs, first-person and top-down captures, the goal-resistance and crossing diagnostics, and earlier integration logs. `check-final.log` is the authoritative current test run; initial import logs may retain errors from before the scene existed. Artifacts are ignored by Git and Godot. Downloaded research PDFs are separately retained under `docs/research/papers/`, with source URLs and checksums in `docs/research/SOURCES.md`.

## Still open

Human gathering/turning/recovery feel, selection of the simplest enjoyable preset, the preferred goal threshold, and the full M0 gate remain open. No darkness/adaptation, XR staff, headset/stereo test, Windows export, submission package, publishing or remote deployment has been performed.
