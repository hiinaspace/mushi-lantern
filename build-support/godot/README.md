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

## Linux release export template

`./tools/build-godot-linux-template.sh` uses the same pinned engine source and
teardown patch, but deliberately does not inherit the nixpkgs editor recipe.
Upstream built-ins, `use_static_cpp=yes`, and `use_sowrap=yes` keep the normal
export-template structure. Embree and the other standard engine features are
retained. Wayland scanner is provided at build time; the upstream-pinned
AccessKit 0.22.3 static SDK preserves screen-reader support.

`build-support/linux-release-toolchain.nix` pins GCC 11 / glibc 2.35 for the
release template and Steam Audio wrapper. The main development shell/editor
pin is unchanged. Nix remains a build tool; the distributed executable uses
`/lib64/ld-linux-x86-64.so.2` and the user's system libraries.

The package audit rejects unexpected ELF files, new system-library dependencies,
Nix loader paths, and symbol requirements above the documented baseline. See
`docs/linux-packaging.md` for the resulting package contract and test evidence.
