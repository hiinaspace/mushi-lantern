# M0b — sleepy mushroom groves

The user judged M0 a successful spike; all three original presets remain useful comparisons. This experiment stays on the same CPU, ground-constrained 3/24-agent fixtures. No terrain, GPU simulation, free flight or XR change is included.

## Behavior

Blue mushroom patches attract and suppress energy, leaving nearby mushi mostly still. Orange quickly raises energy and weakens mushroom attraction while illuminated, allowing extraction. Blue lantern attraction now progressively suppresses locomotion: an illuminated pursuer can fall asleep before reaching the lamp. Away from suppressing fields, energy returns toward neutral, with a small seeded periodic variation per creature. High orange arousal also returns toward neutral.

Body/wing emission follows actual energy: blue dormant, green neutral, yellow through orange aroused. The inspector also names the state and reports mushroom exposure. Mushroom attraction is a local radial field; tree collision remains enforced, but mushroom influence itself is not occlusion-tested. These are resting patches, not physical mushroom perching surfaces.

New presets have gentler goal resistance (0.48 versus the original 0.8), extending 4.2 m beyond the return radius rather than 1.8 m. Both strength and outer width are tunable. Original presets preserve their earlier behavior and have no mushroom sources.

| Preset | Recovery toward neutral | Blue suppression | Orange arousal |
| --- | --- | --- | --- |
| Energy recovery (3, default) | 12.8 s | 3.54 s | 0.29 s |
| Lingering energy (4) | 32.9 s | 3.54 s | 0.29 s |

Times are unopposed 90% response times at full stimulus, not promised time-to-sleep or time-to-wake. Competing fields blend their rates and targets; beam edges act more weakly. Live sliders expose these times and mushroom pull; named snapshots retain the full coefficients, seed and fixture. Energy presets reset to clear light so the dormant starting state is visible.

## Short feel test

1. Start `./launch.sh --tiny --preset 3`. Observe the blue resting group, then use orange (3) to extract it from the patch.
2. Switch to blue (2) to gather the group; keep it illuminated long enough to see whether settling creates a useful reason to switch back to orange.
3. Close the shutter or switch clear (1), observing gradual recovery toward green. Compare Lingering energy at the same seed.
4. Push a group into the goal. Judge whether its broader resistance is readable rather than an abrupt reversal near the rim.
5. Repeat with Full · 24. Save any promising tuning and a short note. The gate is a readable, enjoyable wake/gather/push loop without excessive waiting or irrecoverable scatter.

## Evidence and limits — 2026-09-21

Godot 4.7.2 Mobile on natto/Radeon 780M. `./check.sh` passes 56 simulation checks and the isolated real-UI save/load/history/reset test, including energy tuning, source visibility and color anchors. Rendered dormant and orange fixtures were inspected; screenshots/logs are in ignored `artifacts/m0b-20260921/`. The orange capture shows the tiny group awake and displaced from its mushrooms after two seconds.

Tests establish bounded behavior and reproducibility, not feel. New M0b human approval remains open; no claim of headset, large population, terrain, or exported-build validation.

## Next gates

After M0b feels useful, try small height-bounded 3D flight at 24/64 agents separately, so vertical steering and swirl can be judged without also changing world scale. Then trial Terrain3D, a wavy heightmap, cylinder trees and measured population scaling before lighting/adaptation. A 256 m square and hundreds/thousands are experiments, not jam promises. See [scale-feasibility.md](scale-feasibility.md).
