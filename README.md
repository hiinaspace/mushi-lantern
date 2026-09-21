# Mushi Lantern — M0b energy lab

A bounded, daylight desktop prototype for testing the core lantern-herding feel before darkness or XR work. Three comparison presets drive the same fixed-step, seeded, finite CPU simulation: plain boids, boids with arousal memory, and independent seekers. The intended motion is loose drifting clusters that gather and stretch under the lantern.

The user found M0 a successful spike without selecting a winner. M0b adds two energy/mushroom experiments while preserving all three original presets. The default is Energy recovery. The current follow-up adds arousal-driven scatter and a 60 m square arena with more travel between mushrooms and the goal.

This remains a small, ground-constrained lab. There is no dark adaptation, forest content, tutorial character, staff physics, networking, or headset claim. Automated checks cover correctness boundaries; selecting a ruleset requires the human playtest in [docs/m0-playtest.md](docs/m0-playtest.md).

## Run

Godot 4.7.2 with the Mobile renderer is the currently verified development runtime on `natto`.

```bash
./launch.sh
```

`launch.sh` uses `$GODOT_BIN`, then `godot4`/`godot` from `PATH`, then the current local 4.7.2 install. Optional launch arguments:

```bash
./launch.sh --tiny
./launch.sh --preset 1
./launch.sh --top-down
./launch.sh --screenshot artifacts/m0-20260921/first-person.png --screenshot-delay 1.5
```

`--preset` uses `0` plain, `1` arousal memory, `2` independent seekers, `3` Energy recovery (default), and `4` Lingering energy. `--mode clear|blue|orange` sets the starting filter. Screenshot capture requires a rendered window; headless mode has no viewport texture.

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

The panel switches comparison presets, selects the three-agent or 24-agent fixture, changes the seed, exposes live behavior controls, and saves/loads named tuning snapshots. `Goal resistance = 0` preserves the original control; its nonzero default tests whether entering the return circle should require deliberate pressure. Tuning changes are timestamped in the current run's configuration history so the record does not silently imply one fixed configuration.

Run records are JSON Lines at `user://m0_run_records.jsonl`; named presets are at `user://m0_saved_presets.json`. Each record includes the actual coefficients and live multipliers, seed, fixture, elapsed time, returns, time in each lantern mode, and the optional panel note. On Linux the default `user://` root is usually `~/.local/share/godot/app_userdata/Mushi Lantern — M0 Herding Lab/`.

## Verify

```bash
./check.sh
```

The suite includes 64 simulation checks and an isolated test of the real UI save/load, configuration history, CLI selection and reset callbacks. The checks cover deterministic reset, finite/capped motion, shutter behavior, angular/radial masking, attraction/repulsion signs, analytic trunk occlusion, stationary blue arrival and moving-target pursuit, local goal resistance, high-speed trunk collision, snapshot neighbor semantics, one-time lifecycle accounting, active-neighbor exclusion, and a short unattended negative control. The energy checks also cover mushroom settling, orange extraction, blue-induced sleep, recovery, energy bounds, and legacy compatibility. These checks do not establish whether herding feels good.

Project and jam scope are recorded in [docs/charter-2026-09-21.md](docs/charter-2026-09-21.md) and [docs/jam-plan.md](docs/jam-plan.md).

Local papers and a practical parameter-comparison note are in [docs/research/M0-movement-note.md](docs/research/M0-movement-note.md). Current evidence and goal-resistance comparisons are in [docs/m0-validation.md](docs/m0-validation.md).

The current behavior, tuning defaults and short test card are in [docs/m0b-energy.md](docs/m0b-energy.md). The proposed small-3D → terrain/population → lighting sequence and GPU/addon research are in [docs/scale-feasibility.md](docs/scale-feasibility.md).
