#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ -n "${GODOT_BIN:-}" ]]; then
  godot_bin="$GODOT_BIN"
elif command -v godot4 >/dev/null 2>&1; then
  godot_bin="$(command -v godot4)"
elif command -v godot >/dev/null 2>&1; then
  godot_bin="$(command -v godot)"
else
  echo "Set GODOT_BIN to a Godot 4.7.2 executable with Vulkan support." >&2
  exit 127
fi

# Real windows/RenderingDevice are required; these checks do not initialize XR.
mushi_gpu_data="$(mktemp -d /tmp/mushi-gpu-data.XXXXXX)"
trap 'rm -r -- "$mushi_gpu_data"' EXIT
export XDG_DATA_HOME="$mushi_gpu_data"
export MUSHI_TEST_DATA_ROOT="$mushi_gpu_data"
"$godot_bin" --headless --path "$project_dir" --editor --quit

run_gpu_check() {
  local script="$1" marker="$2"
  local output_file="$mushi_gpu_data/check.log"
  local result=0
  "$godot_bin" --path "$project_dir" --rendering-driver vulkan --rendering-method mobile \
    --disable-vsync --max-fps 60 --quit-after 1800 --script "$script" -- --flat-lab >"$output_file" 2>&1 || result=$?
  cat "$output_file"
  if (( result != 0 )) || ! grep -q "$marker" "$output_file" || grep -Eq 'ERROR:|SCRIPT ERROR:|FAIL|leaked' "$output_file"; then
    return 1
  fi
}

run_gpu_check res://tests/gpu_compute_parity.gd GPU_PARITY_OK
run_gpu_check res://tests/gpu_compute_lifecycle.gd GPU_RESET_OK
run_gpu_check res://tests/glyph_texture_checks.gd 'GLYPH_TEXTURE_CHECKS PASS'
run_gpu_check res://tests/gpu_ui_smoke.gd 'GPU_UI_SMOKE PASS'
