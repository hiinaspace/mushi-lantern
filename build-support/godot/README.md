# Patched Godot for Steam Audio

`./tools/build-godot-audio.sh` builds pinned nixpkgs Godot 4.7.2 with
`0001-retire-audio-before-extension-unload.patch`. That patch was copied from
Prim's `godot-libmpv-zero` revision
`293d895d0e11eca1b3665a654fe4438e2d9ea031` on 2026-09-23.
The resulting `.local/godot/bin/godot4` is selected by `launch.sh` when the
Steam Audio descriptor exists. `GODOT_BIN` remains an explicit override.
