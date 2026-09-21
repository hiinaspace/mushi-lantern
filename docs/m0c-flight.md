# M0c — bounded 3D flight spike

The user approved M0b's arousal/scatter tension and longer travel, then requested moving on to 3D before further ground tuning. This is a small CPU flight experiment, not the terrain or large-population milestone.

## Compare

`./launch.sh --preset 3` starts 24 flying mushi. Select **64** in the panel or use `--count 64`. **3D flight** toggles the ground fallback; `--ground` starts it directly. `--tiny` still provides a three-agent extraction fixture. Saved snapshots record simulation mode and count; older snapshots without a mode load into the ground simulation they were made for.

The same 60 m arena, mushroom fields, energy colors, scatter slider and lantern controls remain. Flight creatures render at 45% of the original linear size. Their rendered height comes from simulated Y, not cosmetic bobbing. Neighbor separation/alignment/cohesion uses XYZ distance. Flight remains bounded below the 3.2 m trunks, with a 2.8 m center-height ceiling; the spike conservatively treats trunks as vertical cylinders for avoidance and light occlusion.

Awake mushi have a gentle, individually varying preferred height near the middle of the flight band. Dormant mushi settle toward the floor. This is a flight control force, not aerodynamic simulation or physical perching on mushroom caps.

Blue seeks a point 3 m along the actual lamp direction, clamped to the flight band. The debug sphere marks that target; the tiled overlay is only a ground slice of the cone, not the full 3D influence. Orange repels from the emitter in 3D. The central return region is a vertical column through the active flight band, with the existing dwell/count-once/ascent lifecycle. Only committed departures may ascend above the active ceiling.

## Human gate

1. Wake a resting patch with orange. Look for readable lift and irregular flight rather than a hovering ground herd.
2. Move and aim blue above/beside the group. Check that vertical gathering and sleep remain understandable, and that orange does not strand creatures against the floor or ceiling.
3. Nudge a greenish group around a trunk and into the return column. Compare recovery/scatter with the ground fallback.
4. Compare 24 and 64. Judge small-body readability and the feel of schooling, not just whether a larger count runs.

A passing correctness test or CPU timing does not approve the feel. Terrain3D, Scatter, hundreds/thousands, GPU work, lighting/adaptation and XR remain later passes.

## Rendered release probe

A retained scripted probe uses the actual tiny fixture and initial lamp pose: three simulated seconds of orange, then seven of clear, followed by a paused inspection camera moved back to include the spread. Final heights were approximately 1.42, 2.04 and 1.65 m. `artifacts/m0c-flight-20260921/capture_release.gd`, `release-render.log` and `release-flight.png` retain the procedure/output. The screenshot is an automated snapshot, not a human gameplay recording or performance measurement.

## Validation and performance boundary

Godot 4.7.2 Mobile on natto/Radeon 780M. `./check.sh` passes **64 ground checks, 18 flight checks, and UI persistence/mode/count checks**. `check-final.log` contains the final source validation, including fixed-step replay, active height bounds, real vertical neighbor response, orange wake/lift, sleeping descent, swept trunk collision, and one-time returns. No parse/runtime errors were found.

The 210-sample active-clear CPU microbenchmark (after 30 warmup ticks) measured 24 agents at 0.273 ms median / 0.370 ms p95 and 64 at 1.172 / 1.266 ms in the final check. These are simulation-only desktop samples, not a sustained renderer or XR budget; background load and CPU frequency vary.

Rendering is the weaker boundary. V-Sync-enabled captures stalled around 1 FPS in this desktop session. Disabling V-Sync avoided that stall, but short live rendered checks still varied: roughly 30–35 FPS for the 64-agent windowed capture, and a 24-agent larger-window capture displayed 20 FPS. Different window sizes/focus and startup state prevent treating these as a count-scaling benchmark. The launcher now disables V-Sync with a 60 FPS cap for this desktop lab. This does not establish an XR presentation fix.

Flying proxy meshes use 12/6 body segments/rings and 8/4 wing/eye segments/rings; only their bodies cast shadows. Static material setup moved out of the per-frame visual update. The flight model is viable at this small CPU scale; **smooth sustained rendering, player feel and headset performance remain unverified**. Profile renderer/frame pacing before increasing population further, rather than treating headless CPU timing as total-frame performance.

Evidence is in ignored `artifacts/m0c-flight-20260921/`. `render-launcher.log`/`flight-24-launcher.png` verify the final launcher, and `render-64-lowpoly.log` records the short unsynchronized 64-agent check. Earlier `render-64*` and `render-24-final.log` retain the stalled diagnostics; two accidentally launched temporary test instances were identified and stopped before the later single-instance checks.
