#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
godot_bin="${GODOT_BIN:-$(command -v godot4 || command -v godot)}"
mushi_env_data="$(mktemp -d /tmp/mushi-environment-check.XXXXXX)"
trap 'rm -r -- "$mushi_env_data"' EXIT
export XDG_DATA_HOME="$mushi_env_data"
"$godot_bin" --headless --xr-mode off --path "$project_dir" --editor --quit
run_check() {
  local mode="$1" script="$2" marker="$3"
  shift 3
  local result=0
  # Persistence checks intentionally save 512/low; each fixture needs its own
  # user directory so the scene-default check starts with clean preferences.
  export XDG_DATA_HOME="$mushi_env_data/${script##*/}"
  mkdir -p "$XDG_DATA_HOME"
  if [[ "$mode" == headless ]]; then
    "$godot_bin" --headless --xr-mode off --path "$project_dir" --script "$script" > "$mushi_env_data/check.log" 2>&1 || result=$?
  else
    "$godot_bin" --xr-mode off --path "$project_dir" --rendering-driver vulkan --rendering-method mobile --disable-vsync --max-fps 60 --quit-after 2400 --script "$script" -- "$@" > "$mushi_env_data/check.log" 2>&1 || result=$?
  fi
  cat "$mushi_env_data/check.log"
  if (( result != 0 )) || ! rg -q "$marker" "$mushi_env_data/check.log" || rg -q 'ERROR:|SCRIPT ERROR:|FAIL' "$mushi_env_data/check.log"; then
    return 1
  fi
}
run_check headless res://tests/environment_settings_checks.gd ENVIRONMENT_SETTINGS_PASS
run_check headless res://tests/adaptation_checks.gd ADAPTATION_OK
run_check headless res://tests/environment_surface_checks.gd ENVIRONMENT_SURFACE_PASS
run_check headless res://tests/environment_traversal_checks.gd ENVIRONMENT_TRAVERSAL_PASS
run_check rendered res://tests/environment_scene_checks.gd ENVIRONMENT_SCENE_PASS
run_check rendered res://tests/gpu_terrain_lifecycle.gd GPU_TERRAIN_LIFECYCLE_OK
run_check rendered res://tests/gpu_cliff_descent.gd GPU_CLIFF_DESCENT_OK
run_check rendered res://tests/gpu_terrain_blue_target.gd GPU_BLUE_TERRAIN_OK
run_check rendered res://tests/gpu_terrain_spawn.gd GPU_TERRAIN_SPAWN_OK
run_check rendered res://tests/night_scene_checks.gd NIGHT_SCENE_PASS --terrain-size 128 --count 512
run_check rendered res://tests/night_scene_checks.gd NIGHT_SCENE_PASS --terrain-size 256 --count 512
run_check rendered res://tests/night_sky_checks.gd NIGHT_SKY_PASS
run_check rendered res://tests/foliage_luminescence_checks.gd FOLIAGE_LUMINESCENCE_PASS
run_check rendered res://tests/glyph_halo_checks.gd GLYPH_HALO_PASS
