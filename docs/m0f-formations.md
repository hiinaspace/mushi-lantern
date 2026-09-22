# M0f — longer drift and a bounded formation experiment

The user accepted GPU Living shoals at 1024 on sayu, then requested promotion of their saved `longer drift` tuning and a brief attempt at smaller, elongated groups before terrain. This pass preserves the accepted tuning as the default and adds a separate experimental preset; it does not implement terrain, networking or an automated parameter-search service.

## Accepted default

`Longer drift` copies the saved base tuning and run controls: 1024 agents, seed 40721, flight, lantern strength 0.8, social multiplier 1.4, wander multiplier 0.5. Compared with Living shoals, glyph scale is 0.4, contagion 0.5, scatter 0.4, mushroom attraction 1.0, blue response 0.365489697300642 and orange response 1.457332337338. The original private saved snapshot remains untouched. F1 tuning and named save/load remain available.

## Design basis and boundary

The existing [movement research](research/M0-movement-note.md) already emphasizes interaction geometry, repulsion zones and local alignment. The previous weak cyclic type preference still averages many neighbors into a common center; it does not establish persistent head/tail arrangements.

[ASAL](https://pub.sakana.ai/asal/) searches over simulation parameters using foundation-model evaluations. Its Particle Life substrate includes type-dependent interaction matrices, while its Boids substrate uses learned local steering. These are broader rule spaces than adjusting three conventional boids weights. This experiment borrows the idea of changing local interaction geometry, not ASAL's search infrastructure or a claim that its published results transfer to this game.

The bounded hypothesis is that directional following plus crowd pressure can encourage strings and reduce dense aggregation while retaining lantern control. No permanent group membership, global leader, or bond graph is introduced. Stable IDs, seeded traits and current position/velocity/energy remain the relevant state for future host snapshots. Local target selection can differ during client reconciliation without requiring a separate reliable bond protocol; multiplayer remains unimplemented.

## Playtest

Compare the accepted default with `Drifting trains` at 1024, same seed. Wake a patch with orange, move the lantern alongside it, then release to clear. Look for small groups separating, sustained heading and readable local following. Reject permanent balls, rigid marching chains, rapid target switching or loss of indirect lantern control. Try 2048 only after that comparison; more agents are not evidence of better forms. F1 exposes the new rule weights for a small manual tuning pass.

Numerical cluster metrics are proximity diagnostics, not a pass/fail test of creature appearance. Screenshots cannot establish sustained behavior. A final human feel check precedes the Terrain3D greybox.

## Implemented rule

`Drifting trains` (preset 7) inherits Longer drift and enables follow weight 0.9, crowd pressure 1.0, sampled crowd threshold 2. Types 0/1/2 act as head/middle/tail: a middle can follow a nearby moving head, a tail a nearby moving middle. The nearest eligible sampled agent must be ahead along its own heading; the target is 0.85 m behind it. There are no permanent leaders, exclusive follower slots or reciprocal bonds, so branching and target changes are possible. This is an exploratory directional bias, not an authored composite body.

Follow weight also reduces broad center-seeking cohesion (67.5% at the preset value). Crowd pressure pushes away from the nearby sampled center inside twice the separation radius. The existing sampler often supplies only three candidates in a dense single cell, hence threshold 2. The F1 threshold is a sampled-neighbor threshold, not a desired final group size. Both weights zero preserve the accepted rules. CPU and GPU implement the same local rule; GPU fixed cell capacity and bounds now support 2048 IDs (8 MiB cell-ID storage).

## Bounded evidence on sayu, 2026-09-22

Stock Godot 4.7.2 nixpkgs, Vulkan Mobile, RTX 4090; same seed 40721 and exact Longer drift multipliers. Each fixture runs 30 simulated seconds at 30 Hz, orange above the first mushroom patch for 10 seconds, then clear for 20 seconds. There is no moving player route. Awake active agents above energy 0.21 are grouped by transitive proximity within 1.5 m. Dormant agents are excluded; different awake populations are an important behavioral difference, not a controlled denominator.

| Population / preset | Awake at 30 s | Proximity components | Groups of 2–12 | Largest group | GPU median / p95 ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1024 Longer drift | 73 | 5 | 1 | 28 | 1.21 / 2.80 |
| 1024 Drifting trains | 425 | 85 | 49 | 78 | 1.35 / 3.22 |
| 2048 Longer drift | 141 | 7 | 1 | 62 | 2.10 / 5.22 |
| 2048 Drifting trains | 856 | 113 | 66 | 175 | 2.28 / 5.10 |

The experiment encourages dispersal and many more small groups, but also keeps substantially more agents awake and away from patches. Its largest group is larger in absolute terms. The screenshots show wider dispersal and remaining source clumps; they do not establish convincing trains or head/tail gestalt. Judge whether this is lively or too scattered before promoting it. Keep 1024 as default: 2048 has a roughly 5 ms GPU p95 in this run, which is a substantial part of a VR frame. These are upload+compute timings, not complete scene or headset frame times; no extra VR headroom claim follows.

Reproduce:

```bash
./check.sh
./check-gpu.sh
MUSHI_FORMATION_CAPTURE_DIR=/home/s/code/mushi-lantern/artifacts/m0f-formations godot --path . --rendering-driver vulkan --rendering-method mobile --disable-vsync --max-fps 60 --quit-after 6000 --script tests/formation_comparison.gd
./launch.sh                         # accepted Longer drift default
./launch.sh --preset 7              # Drifting trains, 1024
./launch.sh --preset 7 --count 2048  # optional population comparison
```

Raw log and captures are ignored local evidence under `artifacts/m0f-formations/`. `check.log` covers the headless checks and named tuning round trips; `check-gpu-final.log` covers rendered parity, lifecycle, UI and reset checks. The first lifecycle test run (`check-gpu.log`) exposed a fixture assumption: the new outward force let one agent leave the small test goal before its dwell completed. The accounting fixture now explicitly encloses the entire spawn cloud in a 4 m goal; gameplay goal size is unchanged. It still requires every agent to commit exactly once, release, and survive a queued 2048-to-64 reset.
