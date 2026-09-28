#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
python3 "$project_dir/scripts/generate_audio_placeholders.py" --if-missing
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

"$godot_bin" --headless --xr-mode off --path "$project_dir" --import
"$godot_bin" --headless --xr-mode off --path "$project_dir" --scene res://scenes/test_runner.tscn


"$godot_bin" --headless --xr-mode off --path "$project_dir" --script res://tests/flight_checks.gd

"$godot_bin" --headless --xr-mode off --path "$project_dir" --script res://tests/population_checks.gd

"$godot_bin" --headless --xr-mode off --path "$project_dir" --script res://tests/height_checks.gd

"$godot_bin" --headless --xr-mode off --path "$project_dir" --script res://tests/glyph_texture_checks.gd

"$godot_bin" --headless --xr-mode off --path "$project_dir" --script res://tests/formation_force_checks.gd

# Exercise the actual UI callbacks without changing the player's saved presets.
mushi_test_data="$(mktemp -d /tmp/mushi-ui-data.XXXXXX)"
trap 'rm -r -- "$mushi_test_data"' EXIT
ui_output="$(XDG_DATA_HOME="$mushi_test_data" MUSHI_TEST_DATA_ROOT="$mushi_test_data" "$godot_bin" --headless --xr-mode off --path "$project_dir" --quit-after 120 --script res://tests/ui_smoke.gd -- --preset 1 2>&1)"
printf '%s\n' "$ui_output"
if [[ "$ui_output" != *"PASS UI:"* || "$ui_output" == *"ERROR:"* ]]; then
  exit 1
fi
