# Steam Audio build provenance

Linux desktop development uses stechyo/godot-steam-audio commit
`8f65c29b21c1d8cdbf2d6dbfc53c92ef95dd2a93`, Valve Steam Audio SDK
4.8.1, godot-cpp commit `4862a9dcf1471c9ea19680b9faadb5b6a9432092`,
and nixpkgs commit `dc5d91f840324650bac8c379428c7037a416959a`.
The source URLs and fixed hashes are in `default.nix`. The five local patches
come from Prim's pinned `godot-libmpv-zero` source checkout, revision
`293d895d0e11eca1b3665a654fe4438e2d9ea031`, copied here on 2026-09-23.
The CMake file is also copied from that revision. These are source inputs, not
a dependency on Prim's mutable checkout.

`./tools/build-steam-audio.sh` builds and stages the Linux x86_64 debug
GDExtension and its Steam Audio runtime into `addons/godot-steam-audio/bin`.
The staged native libraries are ignored by Git; rerun the script after a fresh
clone. The descriptor and icons are tracked. The descriptor lists other upstream
platforms, but only Linux x86_64 debug is built by that recipe.

## Windows x86_64 release extension

The pinned SDK runtime can be staged without a compiler build:

```bash
./build-support/steam-audio/stage-windows-sdk.sh
```

Then build the Windows release GDExtension on x86_64 Linux with Nix:

```bash
./build-support/steam-audio/build-windows.sh
```

The build uses the pinned nixpkgs revision's `pkgsCross.mingwW64` toolchain
and the same pinned extension, godot-cpp, Steam Audio SDK, and patches as the
Linux build. The stage script puts the Windows SDK runtime DLLs and import
library in the addon's `bin` directory. The build script stages those again,
plus `libgodot-steam-audio.windows.template_release.x86_64.dll` and the
`libmcfgthread-2.dll` MinGW threading runtime. These generated binaries are
intentionally ignored by Git and must be staged after a fresh checkout before
Windows export. The matching mcfgthread license files are retained in the Nix
output under `.local/steam-audio-windows/share/licenses/mcfgthread`.

The Steam Audio helper DLLs depend on the Microsoft Visual C++ 2015–2022 x64
redistributable and the OpenCL runtime supplied by the GPU driver. The package
script documents these prerequisites and does not bundle Microsoft's runtime.

The release preset uses this project's patched Godot 4.7.2 Windows template.
Build it with `./tools/build-godot-windows-template.sh`; the package script
does this automatically. The official Windows template is not equivalent,
because it lacks the Steam Audio teardown fix. The pinned custom template
build is documented in `build-support/godot/README.md`.

Export with:

```bash
godot4 --headless --path . --export-release 'Windows OpenXR'
```

The preset writes `artifacts/export/windows/mushi-lantern.exe`. Its include
filter carries the Steam Audio and godot-cpp license notices from this
directory. Export and assemble a ZIP of the EXE, PCK, native DLLs, and notices
with:

```bash
./build-support/steam-audio/package-windows.sh
```

A Wine desktop smoke test can catch packaging/loader mistakes but does not
qualify native Windows or OpenXR PCVR behavior.

The extension is MIT licensed (`UPSTREAM_EXTENSION_LICENSE.md`). The
statically linked godot-cpp binding has its MIT notice in `GODOT_CPP_LICENSE.md`. Steam Audio's
Apache 2.0 license and bundled third party notice are retained as
`STEAM_AUDIO_SDK_LICENSE.md` and `STEAM_AUDIO_SDK_THIRDPARTY.md`. The Nix output
also installs these notices for binary packaging. Include them when distributing
the native libraries.

The matching Godot recipe is `../godot/default.nix`. It adds the audio teardown
patch copied from the same Prim source revision and selects the pinned nixpkgs
Godot 4.7.2. Build it with `./tools/build-godot-audio.sh`; `launch.sh` uses the
result when the extension descriptor is present. The stock Godot exit crash in
the isolated probe establishes a compatibility difference, but does not prove
this patch alone is its cause.
