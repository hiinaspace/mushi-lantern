#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="${GODOT_BIN:-$project_dir/.local/godot/bin/godot4}"
for command_name in pactl parec ffmpeg; do
	command -v "$command_name" >/dev/null || { echo "Missing required command: $command_name" >&2; exit 2; }
done
[[ -x "$godot_bin" ]] || { echo "Godot executable not found: $godot_bin (set GODOT_BIN to the patched build)" >&2; exit 2; }

tmp_dir="$(mktemp -d /tmp/mushi-audio-loudness.XXXXXX)"
sink_name="mushi_lufs_${BASHPID}"
module_id=""
capture_pid=""
game_pid=""
cleanup() {
	[[ -n "$game_pid" ]] && kill "$game_pid" 2>/dev/null || true
	[[ -n "$capture_pid" ]] && kill "$capture_pid" 2>/dev/null || true
	[[ -n "$module_id" ]] && pactl unload-module "$module_id" >/dev/null 2>&1 || true
	rm -rf -- "$tmp_dir"
}
trap cleanup EXIT INT TERM

export XDG_DATA_HOME="$tmp_dir/data"
export XDG_CONFIG_HOME="$tmp_dir/config"
export XDG_CACHE_HOME="$tmp_dir/cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"

module_id="$(pactl load-module module-null-sink sink_name="$sink_name" sink_properties="device.description=Mushi_LUFS_Test")"
capture_file="$tmp_dir/capture.s16le"
parec --device="${sink_name}.monitor" --format=s16le --rate=48000 --channels=2 >"$capture_file" &
capture_pid=$!
sleep 0.2
timeout 70s env PULSE_SINK="$sink_name" "$godot_bin" --path "$project_dir" --xr-mode off --display-driver x11 --audio-driver PulseAudio --rendering-driver vulkan --rendering-method mobile --disable-vsync --max-fps 60 --script tests/audio_loudness_walk.gd -- --desktop --simulation gpu --count 1024 >"$tmp_dir/godot.log" 2>&1 &
game_pid=$!

set +e
wait "$game_pid"
game_status=$?
set -e
game_pid=""
kill "$capture_pid" 2>/dev/null || true
wait "$capture_pid" 2>/dev/null || true
capture_pid=""
if (( game_status != 0 )); then
	tail -n 60 "$tmp_dir/godot.log" >&2
	echo "Rendered audio walk failed with exit status $game_status" >&2
	exit "$game_status"
fi
grep '^AUDIO_' "$tmp_dir/godot.log"
if [[ ! -s "$capture_file" ]]; then
	echo "PulseAudio monitor capture is empty" >&2
	tail -n 60 "$tmp_dir/godot.log" >&2
	exit 1
fi

stats="$(ffmpeg -hide_banner -nostats -f s16le -ar 48000 -ac 2 -i "$capture_file" -af 'loudnorm=I=-14:TP=-1.0:LRA=11:print_format=json' -f null - 2>&1)"
measurements="$(printf '%s\n' "$stats" | sed -n -E 's/.*"input_i"[[:space:]]*:[[:space:]]*"([^"]+)".*/Integrated loudness: \1 LUFS/p; s/.*"input_tp"[[:space:]]*:[[:space:]]*"([^"]+)".*/True peak: \1 dBTP/p')"
if [[ $(printf '%s\n' "$measurements" | wc -l) -lt 2 ]]; then
	echo "ffmpeg did not return integrated LUFS and true peak" >&2
	printf '%s\n' "$stats" >&2
	exit 1
fi
printf '%s\n' "$measurements"
