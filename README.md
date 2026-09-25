# Mushi Lantern — night grove and XR staff

The default scene is a 128 m Terrain3D basin with GPU mushi, coarse trunk/rock collision, static leafy trees and grass, and a persistent F2 quality panel. The 128/256 m maps have 9/18 mushroom patches, about 10% free-starting mushi, and stepped terrain with drop-offs and walking detours. The nighttime pass adds an adapting starfield, a tall green goal beacon, faint foliage luminescence near full dark adaptation, subtle bloom and lantern lighting with very low ambient light. The lantern now hangs from a grabbable staff with desktop and OpenXR controls. Rendering, staff interaction, and spatial audio have been checked on Beyond/Monado; measured headset frame delivery remains a follow-up.

Steam Audio positions a bounded pool of nearby mushi calls, tree insects, footsteps, and lantern cues. Mushi calls are provisionally generated from narrow glass-harp resonances with an insect-like contact edge; nearby moving creatures sound more continuously, while dormant ones stay quiet. Calm calls now play about an octave lower than excited ones, with live pitch-range controls in the audio menu. Generated sounds have a [reproducible generator](assets/audio/placeholders/README.md); the selected field recordings have [source and edit notes](assets/audio/field/README.md) and [sound credits](CREDITS.md). The oil lantern source includes three additional short transients for varied side-to-side filter cues. A [sample audition shortlist](docs/audio-sample-shortlist.md) records other CC0 candidates.

The accepted 1024-agent simulation and F1 tuning sandbox remain. See [docs/m1-environment.md](docs/m1-environment.md) for the environment test card, measurements and known limits, [docs/m1-environment-plan.md](docs/m1-environment-plan.md) for the approved plan, and [docs/m0g-trios.md](docs/m0g-trios.md) for the accepted trios/tuning checkpoint. Terrain3D is vendored at a pinned version; [dependency provenance](docs/terrain3d-provenance.md) includes its reproducible setup command and license.

## Run

The terrain scene is verified with Godot 4.7.2 and the Mobile renderer on `sayu`. Earlier flat-lab work also ran on `natto`; the new environment has not been qualified there.

An experimental two-player, host-authoritative multiplayer slice is available
on Linux. It includes shared lantern influence, synchronized Ukon player poses,
head/arm IK, and lower-body locomotion from the free RPG animation sample.
Headset avatar fit and hand tracking remain to be tested. See
[the transport and CLI instructions](multiplayer-native/README.md) and
[the measured feasibility gate](docs/multiplayer-feasibility-plan.md).

For Steam Audio on Linux x86_64, build the pinned extension and audio-patched
Godot once after cloning:

```bash
./tools/build-steam-audio.sh
./tools/build-godot-audio.sh
```

`launch.sh` and the check scripts generate the placeholder WAVs on first use.
Run `python3 scripts/generate_audio_placeholders.py` before opening a fresh
checkout directly in the Godot editor.

The first command stages native libraries under `addons/godot-steam-audio/bin`;
the second creates `.local/godot/bin/godot4`. Their source revisions, patches,
and notices are in [build-support/steam-audio/README.md](build-support/steam-audio/README.md).
Windows release extensions are built by the Windows package script. Linux
friend exports also require a matching Linux release extension.

```bash
./launch.sh
./launch.sh --xr --count 512 # OpenXR through the active runtime; 512 is a lower-cost first check
```

`launch.sh` disables V-Sync and caps desktop rendering at 60 FPS to avoid an observed presentation stall on natto. OpenXR is disabled by default in the project, avoiding a missing-headset startup dialog; `--xr` explicitly enables it without the desktop FPS cap. With Steam Audio present it uses `.local/godot/bin/godot4` by default. `GODOT_BIN=/path/to/compatible/godot` overrides that selection. Without Steam Audio it falls back to `godot4`/`godot` from `PATH`, then the local 4.7.2 install. Optional launch arguments:

```bash
./launch.sh --tiny
./launch.sh --preset 1
./launch.sh --preset 7 --count 1024 # Drifting trains comparison
./launch.sh --preset 8 --count 1024 # accepted Loose trains default, explicitly selected
./launch.sh --preset 7 --count 2048 # higher population comparison
./launch.sh --count 1024 --simulation gpu
./launch.sh --terrain-size 256
./launch.sh --flat-lab --ground
./launch.sh --top-down
./launch.sh --screenshot artifacts/m0-20260921/first-person.png --screenshot-delay 1.5
```

`--preset` uses `0` plain, `1` arousal memory, `2` independent seekers, `3` Energy recovery, `4` Lingering energy, `5` Living shoals, `6` Longer drift, `7` Drifting trains (stronger-follow comparison), and `8` Loose trains (default). Loose trains uses the accepted 1024-agent tuning; `--preset` and `--count` remain available as overrides. `--mode clear|blue|orange` sets the starting filter. Screenshot capture requires a rendered window; headless mode has no viewport texture.

The terrain scene requires GPU flight with Vulkan Mobile. `--flat-lab` opens the legacy flat comparison; only there do `--simulation cpu|gpu` and `--ground` apply. CPU/ground trajectory compatibility is no longer a terrain requirement. `--saved-preset` can still load a private named snapshot when supplied; explicit `--count` takes precedence. F2 stores local quality preferences without changing named behavioral presets. GPU HUD snapshots are delayed, and its displayed CPU submission time must not be read as GPU execution time. The backend is recorded in run history; named behavioral presets remain independent of the execution backend.

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
| F3 | Audio mix: live Overall/Mushi/Forest/Tool/Steps levels, calm/excited mushi pitch, and one locally saved preset |
| I | Inspect the next agent in the debug HUD |
| F11 | Toggle fullscreen |
| Esc / click | Release / recapture mouse |

In OpenXR, the left stick moves and strafes, and the right stick turns smoothly, with a configurable 0.22 stick dead zone to suppress drift. Grip either hand near the crook-shaped staff shaft to take it at one of six grip positions; release the final shaft grip to float and park it without changing its shutter or filter. XR Tools grip rings highlight the nearby shaft and the short settings rope below the lantern. Grip that rope with a free hand to adjust: move the hand about 10 cm up/down through the full shutter range, with a 2 cm dead zone, and yaw the controller left/center/right to slide the filter between blue/clear/orange. All four lantern faces show the moving filter and shutter bands; the front is brighter, while the rear and sides remain readable with faint colored slits even when fully closed. Blue and the now redder orange filter add opposing chevrons to the windows and beam. Release settles the filter to the nearest color. These motions are measured in a level frame that follows the lantern, so stick locomotion remains active while adjusting. The smaller square lantern uses a soft square spotlight mask; full brightness has no shutter stripes, and partial settings show bands. Its hanging motion is simulated in world space under gravity, with a small amount of XR locomotion inertia compensation and level aim when parked. The ordinary staff grab reach is 0.20 m; pickup, release, setting adjustment and recall give light controller haptics. Y/B on either controller opens the pointer menu with Overall, category, and calm/excited mushi pitch sliders plus local preset saving; pointer lasers are hidden while the menu is closed. Hold X/A for about half a second to recall the parked staff toward that hand; release X/A to settle it onto safe ground near its current position, even if released early, or grip near the hovering staff to take its middle grip point. Opening the menu pauses stick locomotion until the sticks return to neutral. Snap turn is available in the rig script, but the in-game setting and either-hand one-controller locomotion are still follow-ups.

The panel switches comparison presets, selects populations from 3 to 2048 (ground mode capped at 64), changes the seed, exposes live behavior controls, and saves/loads named tuning snapshots. `Goal resistance = 0` preserves the original control; its nonzero default tests whether entering the return circle should require deliberate pressure. Tuning changes are timestamped in the current run's configuration history so the record does not silently imply one fixed configuration.

Run records are JSON Lines at `user://m0_run_records.jsonl`; named presets are at `user://m0_saved_presets.json`. Each record includes the actual coefficients and live multipliers, seed, fixture, elapsed time, returns, time in each lantern mode, and the optional panel note. On Linux the default `user://` root is usually `~/.local/share/godot/app_userdata/Mushi Lantern — M0 Herding Lab/`.

## Verify

```bash
./check.sh
./check-gpu.sh  # retained flat-lab GPU regression checks
./check-environment.sh  # terrain, settings, rendered scene and GPU grounding
./check-audio.sh  # private sink, spatial direction and short 1024-agent source budget
./check-audio.sh --long  # adds 60-second 24-source and repeated reset/teardown checks
./.local/godot/bin/godot4 --headless --xr-mode off --path . --scene res://tests/staff_tool_smoke.tscn --quit-after 120
```

The headless suite includes simulation/texture checks and an isolated test of real UI save/load, configuration history, CLI selection and reset callbacks. `check-gpu.sh` separately checks CPU/GPU agreement, waking and filter transitions, return/release accounting, resets, GPU texture binding and actual scene backend switching. GPU terrain flight uses shared height data, finite trunk/rock proxies and coarse swept overlap correction. `staff_tool_smoke.tscn` checks tool states and gestures. `check-audio.sh` needs `pactl` and a running PulseAudio-compatible server; it routes sound through a temporary null sink and leaves the default sink alone. These checks do not establish herding feel, stereo comfort or export readiness.

Friend builds use separate desktop and VR launchers around the same export.
On Linux, `./build-support/package-linux-friends.sh` creates a ZIP with
`friend-desktop.sh` and `friend-vr.sh`. The Linux release Steam Audio extension
must be built and staged first. On Linux, use
`./build-support/steam-audio/package-windows.sh` to build the patched Windows
template and Steam Audio release extension, then export a ZIP with
`friend-desktop.bat` and `friend-vr.bat`. The Windows ZIP is a Linux-exported
build; Wine smoke tests do not establish native Windows or OpenXR readiness.

Project and jam scope are recorded in [docs/charter-2026-09-21.md](docs/charter-2026-09-21.md) and [docs/jam-plan.md](docs/jam-plan.md).

Local papers and a practical parameter-comparison note are in [docs/research/M0-movement-note.md](docs/research/M0-movement-note.md). Current evidence and goal-resistance comparisons are in [docs/m0-validation.md](docs/m0-validation.md).

The current behavior, tuning defaults and short test card are in [docs/m0b-energy.md](docs/m0b-energy.md). The proposed small-3D → terrain/population → lighting sequence and GPU/addon research are in [docs/scale-feasibility.md](docs/scale-feasibility.md).
