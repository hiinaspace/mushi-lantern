# Mushi Lantern — M0g local trios

The particle simulation is **accepted and checkpointed at M0g**; terrain/environment is next. The runnable tuning options are: the accepted **Longer drift** default at 1024 and a revised **Drifting trains** preset that forms transient reciprocal head/body/tail groups. See [docs/m0g-trios.md](docs/m0g-trios.md) for rules, measurements and the playtest boundary. The earlier M0f exploratory rule is described in [docs/m0f-formations.md](docs/m0f-formations.md). F1 retains the live ALife tuning sandbox. The **M0e** performance pass added shader-driven glyph updates and a stock-Godot compute backend for rendered flight. See [docs/m0e-performance.md](docs/m0e-performance.md) for comparison commands and measured limits. Networking and headset readiness remain unimplemented/unverified by this desktop pass.

GPU flight is the supported development path. CPU flight and ground modes are legacy utilities; preserving or maintaining them is no longer a requirement.

A bounded, daylight desktop prototype for testing the core lantern-herding feel before darkness or XR work. Three comparison presets drive the same fixed-step, seeded, finite CPU simulation: plain boids, boids with arousal memory, and independent seekers. The intended motion is loose drifting clusters that gather and stretch under the lantern.

The user found M0 a successful spike without selecting a winner. M0b adds two energy/mushroom experiments while preserving all three original presets. The original energy comparisons remain available. The current follow-up adds arousal-driven scatter and a 60 m square arena with more travel between mushrooms and the goal.

M0b was approved as a useful herding loop. The default is now Longer drift at 1024 agents: heading-oriented instanced glyphs with live size/billboard controls and adjustable ceiling, seeded trait variation, neighbor arousal and spontaneous waking, with population options through 2048 and the ground fallback. See [docs/m0d-living-shoals.md](docs/m0d-living-shoals.md). See [docs/m0c-flight.md](docs/m0c-flight.md). There is no dark adaptation, forest content, tutorial character, staff physics, networking, or headset claim. Automated checks cover correctness boundaries; selecting a ruleset requires the human playtest in [docs/m0-playtest.md](docs/m0-playtest.md).

## Run

Godot 4.7.2 with the Mobile renderer is the verified desktop runtime on `natto` and `sayu`.

```bash
./launch.sh
```

`launch.sh` disables V-Sync and caps desktop rendering at 60 FPS to avoid an observed presentation stall on natto; sustained rendering/XR performance is not yet approved. It uses `$GODOT_BIN`, then `godot4`/`godot` from `PATH`, then the current local 4.7.2 install. Optional launch arguments:

```bash
./launch.sh --tiny
./launch.sh --preset 1
./launch.sh --preset 7 --count 1024 # Drifting trains experiment
./launch.sh --preset 7 --count 2048 # higher population comparison
./launch.sh --count 1024 --simulation gpu
./launch.sh --ground
./launch.sh --top-down
./launch.sh --screenshot artifacts/m0-20260921/first-person.png --screenshot-delay 1.5
```

`--preset` uses `0` plain, `1` arousal memory, `2` independent seekers, `3` Energy recovery, `4` Lingering energy, `5` Living shoals, `6` Longer drift (default), and `7` Drifting trains (experiment). `--mode clear|blue|orange` sets the starting filter. Screenshot capture requires a rendered window; headless mode has no viewport texture.

`--simulation cpu|gpu` chooses the flight backend (GPU by default in a rendered Vulkan session); the panel can switch it with a same-seed reset. Ground mode uses the CPU. GPU HUD snapshots are delayed, and its displayed CPU submission time must not be read as GPU execution time. The backend is recorded in run history; named behavioral presets remain independent of the execution backend.

## Controls

| Input | Action |
| --- | --- |
| WASD / mouse | Move / look; hold Shift for precise slow movement |
| 1 / 2 / 3 | Clear neutral / blue attract-calm / orange repel-energize |
| F | Toggle shutter |
| [ / ] | Continuously decrease / increase shutter openness |
| R | Reset the same seed, fixture, and layout |
| P | Pause simulation |
| T | Toggle top-down diagnostic camera |
| F1 | Toggle tuning panel and field debug |
| I | Inspect the next agent in the debug HUD |
| F11 | Toggle fullscreen |
| Esc / click | Release / recapture mouse |

The panel switches comparison presets, selects populations from 3 to 2048 (ground mode capped at 64), changes the seed, exposes live behavior controls, and saves/loads named tuning snapshots. `Goal resistance = 0` preserves the original control; its nonzero default tests whether entering the return circle should require deliberate pressure. Tuning changes are timestamped in the current run's configuration history so the record does not silently imply one fixed configuration.

Run records are JSON Lines at `user://m0_run_records.jsonl`; named presets are at `user://m0_saved_presets.json`. Each record includes the actual coefficients and live multipliers, seed, fixture, elapsed time, returns, time in each lantern mode, and the optional panel note. On Linux the default `user://` root is usually `~/.local/share/godot/app_userdata/Mushi Lantern — M0 Herding Lab/`.

## Verify

```bash
./check.sh
./check-gpu.sh  # rendered Vulkan/Mobile checks; requires a desktop display
```

The headless suite includes 129 simulation/texture checks plus two formation-force checks and an isolated test of real UI save/load, configuration history, CLI selection and reset callbacks. `check-gpu.sh` separately checks CPU/GPU agreement, waking and filter transitions, return/release accounting, resets, GPU texture binding and actual scene backend switching. The CPU reference retains its swept trunk collision checks; GPU flight deliberately uses coarse pushout. These checks do not establish herding feel, stereo comfort or export readiness.

Project and jam scope are recorded in [docs/charter-2026-09-21.md](docs/charter-2026-09-21.md) and [docs/jam-plan.md](docs/jam-plan.md).

Local papers and a practical parameter-comparison note are in [docs/research/M0-movement-note.md](docs/research/M0-movement-note.md). Current evidence and goal-resistance comparisons are in [docs/m0-validation.md](docs/m0-validation.md).

The current behavior, tuning defaults and short test card are in [docs/m0b-energy.md](docs/m0b-energy.md). The proposed small-3D → terrain/population → lighting sequence and GPU/addon research are in [docs/scale-feasibility.md](docs/scale-feasibility.md).
