# Mushi Lantern

Guide drifting mushi home through a quiet, dark forest with a lantern.
A short tutorial introduces the grove, the light vein beneath it, and the
lantern's blue attraction and red repulsion. There are no jumpscares or hostile
creatures. Play on a desktop or with a PC OpenXR headset.

**[Game and downloads on itch.io](https://hiina.itch.io/mushi-lantern)**

The jam build includes a night-adapting sky and forest, a GPU simulation of
1,024 mushi, spatial audio, and experimental peer-to-peer multiplayer for up to
**eight players**. Multiplayer offers a shared shrine or a two-shrine mode,
spatial voice, and tracked avatars. The host runs the simulation; clients
receive snapshots. LAN/WAN conditions and headset performance can vary.

## Controls

| Desktop | Action |
| --- | --- |
| WASD / mouse | Move / look; Shift slows movement; Space jumps |
| Hold left mouse | Aim the staff |
| Hold right mouse + drag | Operate the lantern rope: up/down opens/closes the shutter, left/right changes blue/clear/red filter |
| G / hold E | Park or pick up the staff / recall it |
| Enter or left click | Advance tutorial dialogue when prompted |
| Esc | Open/close the tabbed menu |
| F11 | Fullscreen |

In VR, grip the staff with either hand and use your free hand to grip the
short control rope. Move it up/down for the shutter and twist left/right for
the filter. Left stick moves; right stick uses **snap turning by default**.
The Comfort tab offers smooth turning and either-hand one-controller
locomotion. Y/B opens the pointer menu, including Skip tutorial. Either trigger
advances dialogue when prompted. Hold X/A to recall a parked staff.
Two-hand broom flight is available only in multiplayer.

F1 opens simulation tuning, F2 quality, F3 audio, and F6 the desktop spectator
camera. Spectator controls and capture options are documented in
[the camera notes](docs/presentation-sprint-2026-09-26.md). Other development shortcuts
include P (pause), T (top-down) and I (inspect agent).

## Build and run from source

The reproducible build scripts currently target **Linux x86_64**, with Windows
x86_64 cross-export support. They use Nix with flakes enabled and pinned public
sources. A private Prim checkout is **not required**. GPU flight requires a
Vulkan-capable GPU; VR additionally needs an active OpenXR runtime.
Allow disk space and time for the patched Godot and native dependencies.

```bash
git clone https://github.com/hiinaspace/mushi-lantern.git
cd mushi-lantern
./tools/build-steam-audio.sh
./tools/build-godot-audio.sh
nix develop . --command ./multiplayer-native/build.sh release
python3 tools/fetch-viseme-runtime.py --platform linux
./launch.sh --desktop
# Or:
./launch.sh --xr
```

The engine is pinned to Godot 4.7.2 with an audio teardown patch. The build
scripts stage generated binaries in ignored directories. `launch.sh` creates
procedural placeholder WAVs and imports assets on first use. Before opening
a fresh checkout directly in the editor, run
`python3 scripts/generate_audio_placeholders.py`. Set `GODOT_BIN` only if you
have a compatible patched engine. See [audio/engine build provenance](build-support/steam-audio/README.md).

The wider light vein tuning is already the default. Useful optional arguments:

```bash
./launch.sh --desktop --tutorial --visual-tuning
./launch.sh --desktop --skip-tutorial
./launch.sh --xr --count 512
./launch.sh --terrain-size 256
./launch.sh --screenshot artifacts/capture.png --screenshot-delay 5
```

Named presets, settings and run records live in Godot's local `user://` data
directory and are not part of this repository. Desktop rendering is capped
at 60 FPS; XR uses the runtime's frame pacing. Lower population and quality
settings provide a performance fallback. CPU submission timings are not GPU
timings or proof of headset performance.

## Multiplayer and exports

Open Multiplayer, choose Classic or Two shrines, then Host or Join with the
same private room code. Multiplayer is experimental P2P; no accounts, host
migration or dedicated server are provided. Short common room codes are easy
to guess. See [native transport, voice and build notes](multiplayer-native/README.md).

```bash
./tools/build-steam-audio-release.sh
nix develop . --command ./multiplayer-native/build.sh release
./build-support/package-linux-friends.sh
```

Linux packaging builds the matching export template and bundles its runtime.
Windows packaging requires a separately staged Windows GNU Rust/MinGW/Opus
toolchain; its environment variables and package command are documented in the
[native build notes](multiplayer-native/README.md). Exported desktop and VR
launchers share a package. Wine smoke tests do not establish native Windows
OpenXR compatibility.

## Checks and project history

```bash
GODOT_BIN="$PWD/.local/godot/bin/godot4" ./check.sh
./check-environment.sh
./check-audio.sh
```

These exercise code, UI, rendering and audio invariants. Audio checks need
`pactl` and a PulseAudio-compatible server. They do not replace human gameplay,
comfort or headset checks. The `docs/` directory also contains historical
plans, experiments and machine-specific evidence; older notes may describe
features or controls superseded by the jam build.

## Credits, inspiration and AI disclosure

Made by Hiina. Mushi Lantern is an unofficial project inspired by
**Mushishi** by Yuki Urushibara, especially its atmosphere and the idea of a
light vein. It is not affiliated with or endorsed by the original creators.
No footage, music, manga panels or character models from that work are bundled.

AI assistance was used extensively for programming, writing and procedural
asset workflows. See [credits](CREDITS.md) and [forest asset provenance](assets/forest/PROVENANCE.md)
for the human-made assets, recordings, models, fonts and libraries used.

## License

Original project work is released under [the Unlicense](UNLICENSE).
**Third-party assets and code retain their own licenses**; the Ukon model in
particular requires attribution and uses custom VRoid Hub terms. Read
[license scope and third-party notices](LICENSES.md) before reusing components.
