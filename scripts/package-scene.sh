#!/usr/bin/env bash
set -euo pipefail
# Local runtime-pack smoke: uses an installed Godot, not a standalone game export.
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="${GODOT_BIN:-$(command -v godot4 || command -v godot)}"
output_dir="${1:-$repo_root/artifacts/m1-environment/package}"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
stage="$(mktemp -d /tmp/mushi-package-source.XXXXXX)"
trap 'rm -r -- "$stage"' EXIT
python3 - "$repo_root" "$stage" <<'PY'
import pathlib, shutil, sys
source, stage = map(pathlib.Path, sys.argv[1:])
for folder in ('scripts', 'shaders', 'scenes', 'addons', 'assets'):
    shutil.copytree(source / folder, stage / folder)
for filename in ('project.godot', 'export_presets.cfg', 'CREDITS.md'):
    shutil.copy2(source / filename, stage / filename)
# VRM and MToon must stay enabled for the fresh-stage VRM import. Terrain3D's
# editor plugin leaks a preview RID on headless exit; its runtime stays enabled.
p = stage / 'project.godot'
import re
p.write_text(re.sub(r'(?m)^enabled=PackedStringArray\([^\n]*\)$', 'enabled=PackedStringArray("res://addons/Godot-MToon-Shader/plugin.cfg", "res://addons/vrm/plugin.cfg")', p.read_text(), count=1))
PY
# Godot's export command imports a fresh project itself. A separate headless
# editor import crashes in this 4.7.2 build while generating GDExtension docs.
"$godot_bin" --headless --path "$stage" --export-pack 'Linux Desktop' "$output_dir/mushi-lantern.pck"
mkdir -p "$output_dir/addons/terrain_3d/bin"
cp --remove-destination "$repo_root/addons/terrain_3d/bin/libterrain.linux.debug.x86_64.so" "$output_dir/addons/terrain_3d/bin/"
cp --remove-destination "$repo_root/addons/terrain_3d/bin/libterrain.linux.release.x86_64.so" "$output_dir/addons/terrain_3d/bin/"
cp --remove-destination "$repo_root/addons/terrain_3d/LICENSE.txt" "$output_dir/Terrain3D-LICENSE.txt"
mkdir -p "$output_dir/addons/godot-steam-audio/bin"
cp --remove-destination "$repo_root/addons/godot-steam-audio/bin/libgodot-steam-audio.linux.template_debug.x86_64.so" "$output_dir/addons/godot-steam-audio/bin/"
cp --remove-destination "$repo_root/addons/godot-steam-audio/bin/libgodot-steam-audio.linux.template_release.x86_64.so" "$output_dir/addons/godot-steam-audio/bin/"
cp --remove-destination "$repo_root/addons/godot-steam-audio/bin/libphonon.so" "$output_dir/addons/godot-steam-audio/bin/"
cp --remove-destination "$repo_root/CREDITS.md" "$output_dir/CREDITS.md"
printf 'Runtime pack: %s\nRun from this directory with: godot --main-pack mushi-lantern.pck\n' "$output_dir"
