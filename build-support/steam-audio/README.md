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
platforms, but only Linux x86_64 debug is built by this recipe. Release and
Windows export need separate pinned builds and tests.

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
