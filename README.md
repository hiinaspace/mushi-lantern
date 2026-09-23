# Mushi Lantern — night grove and XR staff

The default scene is a 128 m Terrain3D basin with GPU mushi, coarse trunk/rock collision, static leafy trees and grass, and a persistent F2 quality panel. The 128/256 m maps have 9/18 mushroom patches, about 10% free-starting mushi, and stepped terrain with drop-offs and walking detours. The nighttime pass adds an adapting starfield, a tall green goal beacon, faint foliage luminescence near full dark adaptation, subtle bloom and lantern lighting with very low ambient light. The lantern now hangs from a grabbable staff with desktop and OpenXR controls. Headset interaction and frame delivery still need a human check.

The accepted 1024-agent simulation and F1 tuning sandbox remain. See [docs/m1-environment.md](docs/m1-environment.md) for the environment test card, measurements and known limits, [docs/m1-environment-plan.md](docs/m1-environment-plan.md) for the approved plan, and [docs/m0g-trios.md](docs/m0g-trios.md) for the accepted trios/tuning checkpoint. Terrain3D is vendored at a pinned version; [dependency provenance](docs/terrain3d-provenance.md) includes its reproducible setup command and license.

## Run

The terrain scene is verified with Godot 4.7.2 and the Mobile renderer on `sayu`. Earlier flat-lab work also ran on `natto`; the new environment has not been qualified there.

```bash
./launch.sh
./launch.sh --xr --count 512 # OpenXR through the active runtime; 512 is a lower-cost first check
```

`launch.sh` disables V-Sync and caps desktop rendering at 60 FPS to avoid an observed presentation stall on natto. `--xr` enables OpenXR without the desktop FPS cap. It uses `$GODOT_BIN`, then `godot4`/`godot` from `PATH`, then the current local 4.7.2 install. Optional launch arguments:

```bash
./launch.sh --tiny
./launch.sh --preset 1
./launch.sh --preset 7 --count 1024 # Drifting trains experiment
./launch.sh --preset 7 --count 2048 # higher population comparison
./launch.sh --count 1024 --simulation gpu
./launch.sh --terrain-size 256
./launch.sh --preset 7 --saved-preset "loose trains" --count 1024
./launch.sh --flat-lab --ground
./launch.sh --top-down
./launch.sh --screenshot artifacts/m0-20260921/first-person.png --screenshot-delay 1.5
```

`--preset` uses `0` plain, `1` arousal memory, `2` independent seekers, `3` Energy recovery, `4` Lingering energy, `5` Living shoals, `6` Longer drift (default), and `7` Drifting trains (experiment). `--mode clear|blue|orange` sets the starting filter. Screenshot capture requires a rendered window; headless mode has no viewport texture.

The terrain scene requires GPU flight with Vulkan Mobile. `--flat-lab` opens the legacy flat comparison; only there do `--simulation cpu|gpu` and `--ground` apply. CPU/ground trajectory compatibility is no longer a terrain requirement. `--saved-preset "loose trains"` loads the existing private named preset if present; explicit `--count` takes precedence. F2 stores local quality preferences without changing named behavioral presets. GPU HUD snapshots are delayed, and its displayed CPU submission time must not be read as GPU execution time. The backend is recorded in run history; named behavioral presets remain independent of the execution backend.

## Controls

| Input | Action |
| --- | --- |
| WASD / mouse | Move / look; hold Shift for precise slow movement |
| Hold left mouse | Wave and aim the staff; release to resume mouse look |
| Mouse wheel or [ / ] | Continuously open / close the shutter |
| G | Drop/park the staff, or pick it up when nearby |
| Hold E | Recall a parked staff toward the camera; release to let it settle again |
| 1 / 2 / 3 | Transition to clear neutral / blue attract-calm / orange repel-energize |
| F | Toggle shutter |
| R | Reset the same seed, fixture, and layout |
| P | Pause simulation |
| T | Toggle top-down diagnostic camera |
| F1 | Toggle tuning panel and field debug |
| F2 | Quality panel: 512/1024, vegetation, shadows, bloom and 3D render scale |
| I | Inspect the next agent in the debug HUD |
| F11 | Toggle fullscreen |
| Esc / click | Release / recapture mouse |

In OpenXR, the left stick moves and strafes, and the right stick turns smoothly. Grip either hand near the staff shaft to take it at one of three grip positions; release the final shaft grip to float and park it. Grip with a free hand near the hanging lantern to adjust it: relative pitch changes shutter openness, and relative roll selects blue, clear or orange. Y/B on either controller opens the pointer menu, currently a control placeholder. Hold X/A for about half a second to recall the parked staff toward that hand; release X/A to settle it or grip the shaft to keep it. The menu and lantern gesture pause stick locomotion until the sticks return to neutral. Snap turn is available in the rig script, but the in-game setting and either-hand one-controller locomotion are still follow-ups.

The panel switches comparison presets, selects populations from 3 to 2048 (ground mode capped at 64), changes the seed, exposes live behavior controls, and saves/loads named tuning snapshots. `Goal resistance = 0` preserves the original control; its nonzero default tests whether entering the return circle should require deliberate pressure. Tuning changes are timestamped in the current run's configuration history so the record does not silently imply one fixed configuration.

Run records are JSON Lines at `user://m0_run_records.jsonl`; named presets are at `user://m0_saved_presets.json`. Each record includes the actual coefficients and live multipliers, seed, fixture, elapsed time, returns, time in each lantern mode, and the optional panel note. On Linux the default `user://` root is usually `~/.local/share/godot/app_userdata/Mushi Lantern — M0 Herding Lab/`.

## Verify

```bash
./check.sh
./check-gpu.sh  # retained flat-lab GPU regression checks
./check-environment.sh  # terrain, settings, rendered scene and GPU grounding
godot --headless --xr-mode off --path . --scene res://tests/staff_tool_smoke.tscn --quit-after 120
```

The headless suite includes simulation/texture checks and an isolated test of real UI save/load, configuration history, CLI selection and reset callbacks. `check-gpu.sh` separately checks CPU/GPU agreement, waking and filter transitions, return/release accounting, resets, GPU texture binding and actual scene backend switching. GPU terrain flight uses shared height data, finite trunk/rock proxies and coarse swept overlap correction. `staff_tool_smoke.tscn` checks tool states and gestures. These checks do not establish herding feel, stereo comfort or export readiness.

The `Windows OpenXR` export preset includes the Terrain3D Windows x86-64 GDExtension. With Godot 4.7.2 export templates installed, export from the editor or run `godot --headless --xr-mode off --path . --export-release "Windows OpenXR" artifacts/export/windows/mushi-lantern.exe`. Launch that build with `--xr` on a Windows OpenXR runtime. The preset has not yet been exported or tested on Windows.

Project and jam scope are recorded in [docs/charter-2026-09-21.md](docs/charter-2026-09-21.md) and [docs/jam-plan.md](docs/jam-plan.md).

Local papers and a practical parameter-comparison note are in [docs/research/M0-movement-note.md](docs/research/M0-movement-note.md). Current evidence and goal-resistance comparisons are in [docs/m0-validation.md](docs/m0-validation.md).

The current behavior, tuning defaults and short test card are in [docs/m0b-energy.md](docs/m0b-energy.md). The proposed small-3D → terrain/population → lighting sequence and GPU/addon research are in [docs/scale-feasibility.md](docs/scale-feasibility.md).
