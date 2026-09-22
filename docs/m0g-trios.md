# M0g — local three-glyph bodies

The user found the M0f `Drifting trains` experiment still looked like insect clumps, even with its exposed weights raised. This pass keeps the accepted 1,024-agent `Longer drift` default and its 0.4 glyph scale. Preset 7 is a revised comparison for small head/body/tail groups. F1 remains a sandbox, and the user's saved tuning snapshots were not edited.

## Rule

Roles 0/1/2 propose nearby head/body and body/tail partners. Every six simulation ticks, a separate compute pass searches the bounded population, retains a valid nearby partner, and accepts only reciprocal proposals. Each role has at most one slot on either side. At that refresh, links dissolve if a partner is no longer active, falls asleep, or moves beyond 4 m; new links start within 3.2 m. No fixed ID grouping, authored spawn trio, or permanent bond is used. A new proposal skips a neighbor whose corresponding old slot remains occupied. Reset clears all links; turning follow to zero also clears them on the next tick.

Followers steer to a 0.18 m slot behind their predecessor, match its velocity, and have weaker independent wandering, lantern/mushroom force and broad social pull while linked. Heads keep the existing drifting response. Immediate and second-degree members are exempt from repulsion and crowd splitting so the intended three glyphs can sit within visual range. The revised experimental preset uses follow weight 1.35, crowd pressure 1.0, sampled crowd threshold 2. The F1 threshold label now says `Crowd threshold`: **lower values split more**. Its count is based on sampled non-partners and does not promise a final group size.

The two unused floats in each agent's GPU state hold predecessor/successor ID + 1; zero means empty. This state is visible in delayed snapshots. A future host could send these as compact metadata with positions/velocities and reconcile clients without a reliable permanent-bond protocol. Networking is not implemented.

The reciprocal matching pass costs more than the ordinary boid sampler; it runs at 5 Hz. There is no engine patch. A previously hidden awake-state mismatch in the GPU rotated cell probe was corrected by using floor-mod for negative grid coordinates; CPU/GPU awake parity now passes the existing short fixture. The PC VR budget still needs a headset and full-scene profile.

## Bounded comparison on sayu

Godot 4.7.2, Vulkan Mobile, RTX 4090, seed 40721, 1,024 agents. Both 30-second routes hold an orange lantern over one mushroom patch for 10 s, then clear for 20 s, with social 1.4, wander 0.5 and lantern 0.8. This is one fixed intervention, not a player herding trial.

| At 30 s | Awake | Independent ordered trios | Complete reciprocal trios | Largest proximity group | GPU upload+compute p50 / p95 / p99 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Longer drift | 75 | 0 | 0 | 28 | 2.47 / 3.71 / 3.83 ms |
| Revised Drifting trains | 436 | 53 | 124 | 34 | 2.44 / 3.99 / 5.02 ms |

The independent trio count uses only positions, role types and velocities. Each head→body and body→tail pair must have a longitudinal gap of 0.07–0.23 m, lateral offset at most 0.10 m, and velocity-heading dot product at least 0.75; head to tail must span at least 0.20 m. Each body/tail can be counted once. Of 124 complete reciprocal trios, 53 met that geometric predicate at 30 s. At 15, 20 and 25 s the strict counts were 75, 69 and 54. The new rule also keeps many more agents awake, so these rows do not have equal awake-population denominators. The diagnostic does not establish that a moving creature reads as a fish in headset.

The [close view](../artifacts/m0g-trios/drifting-trains-close.png) uses actual live trio IDs [18,582,702] at the 30 s snapshot with a moved camera; the [wide view](../artifacts/m0g-trios/drifting-trains.png) shows overall dispersion. Both are ignored local evidence, not source assets. The close frame shows several short arrangements, but sustained motion and player feel remain a human check. The extra matching work raised tail latency relative to the accepted default, and 4 ms p95 is already meaningful in a 90 Hz VR frame. No full-scene or headset claim follows.

`./check.sh` passed 129 headless checks, focused formation-force checks and isolated UI validation. `./check-gpu.sh` passed rendered parity, reset/lifecycle, texture and UI checks, including 2,048 awake partner matching. Raw GPU validation output is retained in `artifacts/m0g-trios/check-gpu-final.log`; measured values and exact commands are in `artifacts/m0g-trios/measurements.txt`. The original M0f rule is frozen in the ignored `artifacts/m0g-trios/baseline/` for investigation, not retained as a runtime mode.

Reproduce the comparison:

```bash
MUSHI_FORMATION_FOCUS=default MUSHI_FORMATION_CAPTURE_DIR=/home/s/code/mushi-lantern/artifacts/m0g-trios godot --path . --rendering-driver vulkan --rendering-method mobile --disable-vsync --max-fps 60 --quit-after 6000 --script tests/formation_comparison.gd
MUSHI_FORMATION_FOCUS=1 MUSHI_FORMATION_CAPTURE_DIR=/home/s/code/mushi-lantern/artifacts/m0g-trios godot --path . --rendering-driver vulkan --rendering-method mobile --disable-vsync --max-fps 60 --quit-after 6000 --script tests/formation_comparison.gd
./launch.sh --preset 7 --count 1024
```

An additional isolated rendered UI run (`artifacts/m0g-trios/ui-disable-final.log`) formed awake partners, set the F1 follow slider to zero, and verified both partner slots cleared; it then passed pause, population resize, reset and backend lifecycle checks.

The user has retired CPU flight and ground compatibility as design requirements. Their existing code and selectors remain legacy utilities for now; maintaining trajectory equivalence is no longer an acceptance gate. Further formation work should target GPU behavior directly.

## Accepted particle-simulation checkpoint — 2026-09-22

The user confirmed that the little trios are readable and aesthetic, and explicitly closed particle-simulation work for now. Their saved `loose trains` tuning intentionally weakens following so crowds can split and recombine while retaining a composite identity. This is human desktop acceptance; headset/full-scene performance remains unverified.

Verified saved tuning on sayu: 1024 agents, seed 40721, flight enabled; formation follow 0.55, crowd pressure 1.1, crowd threshold 2, contagion 0.45, arousal scatter 0.65, glyph scale 0.6, social multiplier 1.4, wander multiplier 0.8, lantern strength 0.8. Remaining coefficients match the Longer drift-derived preset. The private JSON stays at `/home/s/.local/share/godot/app_userdata/Mushi Lantern — M0 Herding Lab/m0_saved_presets.json`; it is not included in the commit. The built-in launch default remains Longer drift. Launch `./launch.sh --preset 7 --count 1024`, then load `loose trains` in F1 for the accepted personal tuning.

Next task: a bounded Terrain3D/environment greybox at the current arena scale, with heightmap clearance and coarse rock/trunk avoidance. Fine foliage collision is unnecessary; begin with Terrain3D's own foliage/instancing before adding a scatter addon. Preserve the accepted GPU simulation and F1 sandbox; CPU/ground support is no longer required. Measure terrain plus simulation on sayu before larger terrain, darkness/bloom or headset claims. Preserve a practical host-authoritative 2–4-player path, but networking remains a stretch goal. Do not reopen particle morphology or parameter search without a concrete new issue.
