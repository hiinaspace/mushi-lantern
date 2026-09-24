#!/usr/bin/env bash
set -Eeuo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
godot_bin="${GODOT_BIN:-$project_dir/.local/godot/bin/godot4}"
if [[ ! -x "$godot_bin" ]]; then
  echo "Build the patched engine with ./tools/build-godot-audio.sh or set GODOT_BIN." >&2
  exit 127
fi
if [[ ! -f "$project_dir/addons/godot-steam-audio/bin/libgodot-steam-audio.linux.template_debug.x86_64.so" ]]; then
  echo "Build the Steam Audio extension with ./tools/build-steam-audio.sh." >&2
  exit 127
fi
if [[ "${1:-}" != "" && "${1:-}" != "--long" ]]; then
  echo "Usage: ./check-audio.sh [--long]" >&2
  exit 2
fi

probe_dir="$(mktemp -d /tmp/mushi-audio-check.XXXXXX)"
sink="mushi_audio_check_$$"
module="$(pactl load-module module-null-sink sink_name="$sink" rate=48000 channels=2 norewinds=1)"
last_log=""
cleanup() {
  pactl unload-module "$module" >/dev/null || true
  rm -r -- "$probe_dir"
}
show_failure() {
  local status=$?
  if [[ -n "$last_log" && -f "$last_log" ]]; then
    tail -n 80 "$last_log" >&2
  fi
  exit "$status"
}
trap cleanup EXIT
trap show_failure ERR
export PULSE_SINK="$sink"

last_log="$probe_dir/spatial.log"
XDG_DATA_HOME="$probe_dir/spatial" timeout 20s "$godot_bin" \
  --display-driver headless --audio-driver PulseAudio --xr-mode off \
  --path "$project_dir" --script res://tests/audio_spatial_smoke.gd \
  > "$probe_dir/spatial.log" 2>&1
rg 'AUDIO_SPATIAL' "$probe_dir/spatial.log"

run_budget() {
  local voices="$1" seconds="$2"
  local disabled=0
  if [[ "$voices" == 0 ]]; then disabled=1; fi
  mkdir -p "$probe_dir/profile-$voices-$seconds"
  last_log="$probe_dir/budget-$voices-$seconds.log"
  XDG_DATA_HOME="$probe_dir/profile-$voices-$seconds" \
    MUSHI_AUDIO_DISABLED="$disabled" \
    MUSHI_AUDIO_STRESS_VOICES="$voices" \
    MUSHI_AUDIO_STRESS_SECONDS="$seconds" \
    timeout 120s "$godot_bin" --path "$project_dir" \
      --display-driver "${MUSHI_AUDIO_DISPLAY_DRIVER:-x11}" --audio-driver PulseAudio \
      --xr-mode off --rendering-driver vulkan --rendering-method mobile \
      --disable-vsync --max-fps 60 --script res://tests/audio_performance.gd \
      -- --desktop --count 1024 > "$probe_dir/budget-$voices-$seconds.log" 2>&1
  rg 'AUDIO_PERF' "$probe_dir/budget-$voices-$seconds.log"
}

run_budget 0 4
run_budget 12 4
run_budget 24 4
if [[ "${1:-}" == "--long" ]]; then
  run_budget 24 60
  mkdir -p "$probe_dir/lifecycle"
  last_log="$probe_dir/lifecycle.log"
  XDG_DATA_HOME="$probe_dir/lifecycle" timeout 60s "$godot_bin" \
    --path "$project_dir" --display-driver "${MUSHI_AUDIO_DISPLAY_DRIVER:-x11}" \
    --audio-driver PulseAudio --xr-mode off --rendering-driver vulkan \
    --rendering-method mobile --disable-vsync --max-fps 60 \
    --script res://tests/audio_lifecycle.gd -- --desktop --count 1024 \
    > "$probe_dir/lifecycle.log" 2>&1
  rg 'AUDIO_LIFECYCLE' "$probe_dir/lifecycle.log"
fi
