# Linux release packaging

The release targets ordinary x86_64 glibc Linux desktops (Ubuntu/Arch-style
installations). Nix is used to build, but no Nix installation is required to
play. NixOS players can use an FHS environment such as `steam-run`.

## Package contract

- Host glibc 2.35+, libstdc++ exporting GLIBCXX_3.4.29 / CXXABI_1.3.11, and libgcc.
- Host Vulkan drivers and normal X11/Wayland/audio libraries. The normal Godot
  dynamically loaded desktop backends are retained, rather than copied into
  the game directory. VR uses the user's selected OpenXR runtime.
- Ordinary `mushi-lantern.x86_64` and `mushi-lantern.pck` at archive root.
- `play-desktop.sh` and `play-vr.sh` simply select a mode and forward game
  arguments. Direct executable launch is also supported. Engine options go
  before `--` when invoking the executable directly.
- No bundled glibc/loader, libsystemd, SDL shared library, graphics drivers,
  desktop audio stack, or dependency on a system Godot installation.

Native components:

```text
mushi-lantern.x86_64 — patched Godot, normal built-in third-party libraries
├── libterrain.linux.release.x86_64.so — Terrain3D
├── libgodot-steam-audio.linux.template_release.x86_64.so
│   └── libphonon.so — Steam Audio SDK (one copy)
└── libmushi_multiplayer_native.so
    ├── Iroh/pkarr — compiled in; P2P connections/discovery
    ├── godot-network-audio / Opus — compiled in; voice
    └── lib/libonnxruntime.so — dynamically loaded; avatar mouth-shape inference
        └── lib/libonnxruntime_providers_shared.so — SDK provider support
```

These edges describe purpose, not just ELF `DT_NEEDED`: Godot loads its
extensions and the multiplayer extension loads ONNX dynamically. Every ELF's
actual dependencies, maximum versioned-symbol requirements, size, purpose and
SHA-256 are recorded in `native-libraries.json` inside the archive.

## Rebuilding

Follow the source-build prerequisites in the root README, then:

```sh
./tools/build-steam-audio-release.sh
nix develop . --command ./multiplayer-native/build.sh release
python3 tools/fetch-viseme-runtime.py --platform linux
./build-support/package-linux.sh
```

The packager builds the export template through Nix (cached when unchanged),
exports the PCK and native extensions using Godot's normal flat library layout,
normalizes relative library search paths, validates the explicit inventory,
and creates `artifacts/export/linux/Mushi-Lantern-Linux.zip`.

The engine source and audio patch match the development engine. The Linux
release uses a separate pinned GCC 11 / glibc 2.35 toolchain. Upstream default
built-in dependencies and dynamically loaded desktop backends replace the
Nix distribution-style engine's shared dependency closure. Standard features,
including Embree, Wayland, SDL and AccessKit, are retained. This is not a
minimal-feature engine build.

The Steam Audio wrapper also uses the older toolchain. The other staged native
artifacts must pass the same ABI audit; rebuilding them in a newer development
shell is permitted only if their resulting requirements remain within the
baseline. The audit fails rather than quietly adding a private runtime.

To check an extracted package without changing it:

```sh
python3 build-support/bundle-linux-runtime.py /path/to/Mushi-Lantern-Linux \
  --patchelf "$(command -v patchelf)" --check-only
```

## Why the previous package was unusual

The old template inherited nixpkgs' system-library configuration. A recursive
bundler collected its desktop libraries, then a second step copied a complete
glibc 2.43 runtime. The launchers invoked that private loader, requiring a
loader-named PCK and nested extension layout. It included 127 ELF files and two
copies of the Steam Audio SDK. `libsystemd` came through D-Bus; the separate
Opus library came through PulseAudio/libsndfile rather than our statically
linked voice codec. The current manifest-based policy replaces that approach.

Historical documents describing friend builds remain historical. Current
package scripts, launchers and generated READMEs use release naming.

## Validation

Verified on 2026-09-29, archive SHA-256:
`b21a6b232ff0ccc3651769e60babf8a90f6f58cef8f8ea73f08105604bf308d8`.

- ZIP integrity and explicit ELF/ABI/hash audit passed: 7 ELF files, 44 files
  total, 181.5 MiB compressed / 301.3 MiB unpacked. Previous archive: 127 ELF
  files, 160 files, 244.8 MiB / 471.4 MiB.
- Ubuntu 22.04 container (glibc 2.35, distro libstdc++): the exported game
  started headlessly and exited 0; Python ctypes loaded all six native shared
  libraries successfully. No Nix filesystem was mounted into the container.
- Natto Ubuntu 26.04.1, with `/nix` hidden using bubblewrap and inherited
  loader variables removed: Wayland direct launch and the shipped desktop
  launcher through X11/Xwayland rendered the grove using Vulkan 1.4.335 on
  the Radeon 780M (RADV PHOENIX), captured screenshots, and exited 0.
- The isolated Sway test compositor lacks optional icon/FIFO protocols;
  Wayland logged those warnings. The final GLES2 compositor runs showed no
  Vulkan surface errors. An initial pixman-compositor attempt could not
  present Vulkan through Xwayland (no DRI3); changing the test compositor,
  not the game, resolved that harness limitation.
- A separate tiny test PCK, run with byte-identical packaged engine and native
  libraries, exercised ONNX inference on both Ubuntu hosts: 119 inference
  hops, status `ready`. Release templates ignore external `--script`
  overrides, so this test used its own main-scene PCK rather than claiming
  that an ignored command-line test had run. This probe is not shipped.
- Two actual exported game processes connected over localhost with `/nix`
  hidden; host and client both reported `Private game · 2 players` and exited
  0. This was a headless transport/startup check, not a GPU snapshot or WAN
  qualification; microphones were not unmuted.
- A clean-context subagent independently inspected the actual ZIP and approved
  the final artifact: a normal Linux Godot game with native feature libraries,
  with no packaging blockers. Its one documentation correction (CXXABI floor)
  was incorporated and re-reviewed.

Commands, logs, screenshots and the independent-review record are retained in
ignored `artifacts/linux-portability-2026-09-29/`. The subsequent Windows review also caught an unrelated root screenshot in
both PCKs. `mpv-shot*.jpg` is now excluded from both exports, preserving the
local original. The final PCKs were re-reviewed and the final Linux archive
was rendered again on natto. Native ELF binaries are unchanged. Publication
is recorded separately in `docs/release-2026-09-29.md`.
Startup/render checks do not establish headset comfort, audible spatial
quality, WAN behavior, or performance on other hardware.
