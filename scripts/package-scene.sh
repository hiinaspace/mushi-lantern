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
for folder in ('scripts', 'shaders', 'scenes', 'addons'):
    shutil.copytree(source / folder, stage / folder)
for filename in ('project.godot', 'export_presets.cfg'):
    shutil.copy2(source / filename, stage / filename)
# The editor-only Terrain3D plugin leaks a preview RID on headless editor exit.
# Runtime extension loading remains enabled. Do not mutate the working project.
p = stage / 'project.godot'
p.write_text(p.read_text().replace('enabled=PackedStringArray("res://addons/terrain_3d/plugin.cfg")', 'enabled=PackedStringArray()'))
PY
# Godot's export command imports a fresh project itself. A separate headless
# editor import crashes in this 4.7.2 build while generating GDExtension docs.
"$godot_bin" --headless --path "$stage" --export-pack 'Linux Desktop' "$output_dir/mushi-lantern.pck"
mkdir -p "$output_dir/addons/terrain_3d/bin"
cp "$repo_root/addons/terrain_3d/bin/libterrain.linux.debug.x86_64.so" "$output_dir/addons/terrain_3d/bin/"
cp "$repo_root/addons/terrain_3d/bin/libterrain.linux.release.x86_64.so" "$output_dir/addons/terrain_3d/bin/"
cp "$repo_root/addons/terrain_3d/LICENSE.txt" "$output_dir/Terrain3D-LICENSE.txt"
printf 'Runtime pack: %s\nRun from this directory with: godot --main-pack mushi-lantern.pck\n' "$output_dir"
