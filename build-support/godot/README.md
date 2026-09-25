# Patched Godot for Steam Audio

`./tools/build-godot-audio.sh` builds pinned nixpkgs Godot 4.7.2 with
`0001-retire-audio-before-extension-unload.patch`. That patch was copied from
Prim's `godot-libmpv-zero` revision
`293d895d0e11eca1b3665a654fe4438e2d9ea031` on 2026-09-23.
The resulting `.local/godot/bin/godot4` is selected by `launch.sh` when the
Steam Audio descriptor exists. `GODOT_BIN` remains an explicit override.

## Windows release export template

The Windows export needs the same teardown fix as Linux: it calls
`AudioServer::finish()` before GDExtension unload and deletes any playback nodes
that remain after mixer callbacks stop. The release preset points at the custom
template under `.local/godot-windows-template`; do not export it with stock
Godot templates.

Build the pinned Godot 4.7.2 source with the MinGW cross compiler from the
pinned nixpkgs revision:

```bash
./tools/build-godot-windows-template.sh
```

This is a Windows `template_release` build with OpenGL compatibility enabled,
matching the known MinGW route. The helper uses four jobs by default; set
`JOBS=N` to change the bound. The build applies only this project's audio
teardown patch and stages the result in the ignored `.local` directory. The
Windows packaging script runs it automatically before export.
