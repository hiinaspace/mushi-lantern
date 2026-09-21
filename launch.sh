#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
fallback_godot="/home/s/.local/share/godot/4.7.2/Godot_v4.7.2-stable_linux.x86_64"

if [[ -n "${GODOT_BIN:-}" ]]; then
  godot_bin="$GODOT_BIN"
elif command -v godot4 >/dev/null 2>&1; then
  godot_bin="$(command -v godot4)"
elif command -v godot >/dev/null 2>&1; then
  godot_bin="$(command -v godot)"
elif [[ -x "$fallback_godot" ]]; then
  godot_bin="$fallback_godot"
else
  echo "Godot 4 was not found. Set GODOT_BIN to the Godot 4.x executable." >&2
  exit 127
fi

if [[ ! -f "$project_dir/.godot/global_script_class_cache.cfg" ]]; then
  "$godot_bin" --headless --path "$project_dir" --editor --quit
fi

exec "$godot_bin" --path "$project_dir" -- "$@"
